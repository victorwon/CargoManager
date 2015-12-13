//
//  CargoManager.m
//
//  Copyright (c) 2013 Ricardo Sánchez-Sáez (http://sanchez-saez.com/)
//  Copyright (c) 2014 Yang Yubo (http://codinn.com/)
//  All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  1. Redistributions of source code must retain the above copyright notice, this
//     list of conditions and the following disclaimer.
//  2. Redistributions in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation
//      and/or other materials provided with the distribution.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
//  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
//  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
//  DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
//  ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
//  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
//  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
//  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
//  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
//  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

#import "CargoManager.h"
#import "CargoBay.h"


NSString *const CMProductRequestDidReceiveResponseNotification = @"CMProductRequestDidReveiveResponseNotification";


NSString *const CMCannotMakePaymentsAlertTitle = @"In App Purchases are disabled";
NSString *const CMCannotMakePaymentsAlertMessage = @"You can enable them again in Settings.";

NSString *const CMAlertCancelButtonTitle = @"OK";


@interface CargoManager () {
    struct {
      unsigned int recordTransaction    : 1;
      unsigned int downloadUpdated      : 1;
      unsigned int restoredTransactionsDidFinishWithSuccess : 1;
    } _delegateFlags;
}

@property (nonatomic) BOOL isStoreLoaded;
@property (nonatomic) NSArray *cachedProducts;

@end

@implementation CargoManager

static CargoManager *_storeKitManager = nil;

+ (CargoManager *)sharedManager
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^ {
        _storeKitManager = [[CargoManager alloc] init];
    });
    
    return _storeKitManager;
}

- (id)init
{
    if (_storeKitManager) {
        return _storeKitManager;
    }

    if ( !(self = [super init]) ) {
        return nil;
    }

    self.isStoreLoaded = NO;
    
    CargoBay *cargoBay = [CargoBay sharedManager];
    
    __weak CargoManager *weakSelf = self;
    cargoBay.paymentQueueUpdatedTransactionsBlock = ^(SKPaymentQueue *queue, NSArray *transactions) {
        for (SKPaymentTransaction *transaction in transactions) {
            [weakSelf transactionUpdated:transaction];
        }
    };
    
    cargoBay.paymentQueueRemovedTransactionsBlock = ^(SKPaymentQueue *queue, NSArray *transactions) {
        for (SKPaymentTransaction *transaction in transactions) {
            [weakSelf transactionRemoved:transaction];
        }
     };
    
    [cargoBay setPaymentQueueRestoreCompletedTransactionsWithSuccess : ^(SKPaymentQueue *queue) {
        [self restoredCompletedTransactionsWithError:nil];
    } failure: ^(SKPaymentQueue *queue, NSError *error) {
        [weakSelf restoredCompletedTransactionsWithError:error];
    }];
    
    cargoBay.paymentQueueUpdatedDownloadsBlock = ^(SKPaymentQueue *queue, NSArray *downloads) {
        for (SKDownload *download in downloads) {
            [weakSelf downloadUpdated:download];
        }
    };
    
    // Set CargoBay as App Store transaction observer
    [[SKPaymentQueue defaultQueue] addTransactionObserver:cargoBay];

    return self;
}

- (void)dealloc
{
    [[SKPaymentQueue defaultQueue] removeTransactionObserver:[CargoBay sharedManager]];
}

- (void)loadStore
{
    NSArray *identifiers = [self.contentDelegate cargoManagerProductIdentifiers:self];
    
    CargoBay *cargoBay = [CargoBay sharedManager];

    __weak CargoManager *weakSelf = self;

    [cargoBay productsWithIdentifiers:[NSSet setWithArray:identifiers]
                              success: ^(NSArray *products, NSArray *invalidIdentifiers) {
                                  // Store cached products and send notification
                                  weakSelf.cachedProducts = products;
                                  weakSelf.isStoreLoaded = YES;
                                  
                                  [weakSelf _postProductRequestDidReceiveResponseNotificationWithError:nil];
                              } failure: ^(NSError *error) {
                                  // Note error and send notification
                                  weakSelf.isStoreLoaded = NO;
                                  
                                  [weakSelf _postProductRequestDidReceiveResponseNotificationWithError:error];
                              }];
}

// Posts the products received notification.
// If there was an error, it creates the userInfo dictionary and adds the error there
- (void)_postProductRequestDidReceiveResponseNotificationWithError:(NSError *)error
{
    NSDictionary *notificationInfo = nil;
    if (error) {
        notificationInfo = @{ @"error" : error };
    }
    
    NSNotification *notification = [NSNotification notificationWithName:CMProductRequestDidReceiveResponseNotification
                                                                 object:self
                                                               userInfo:notificationInfo];
    [[NSNotificationCenter defaultCenter] postNotification:notification];
}

- (void)transactionUpdated:(SKPaymentTransaction *)transaction
{
    // DLog(@"{ transaction.transactionState: %d }", transaction.transactionState);
    switch (transaction.transactionState) {
        case SKPaymentTransactionStatePurchased: {
            __weak CargoManager *weakSelf = self;
            [[CargoBay sharedManager] verifyTransaction:transaction
                                               password:nil
                                                success:
             ^(NSDictionary *receipt)
            {
                // DLog(@"Transaction verified.");
                [weakSelf completeTransaction:transaction];
            }
                                                failure:
             ^(NSError *error)
            {
                // DLog(@"Transaction vertification failed.");
                [weakSelf transactionFailed:transaction];
            }];
        } break;
            
        case SKPaymentTransactionStateFailed:
            [self transactionFailed:transaction];
            break;
            
        case SKPaymentTransactionStateRestored: {
            __weak CargoManager *weakSelf = self;
            [[CargoBay sharedManager] verifyTransaction:transaction
                                               password:nil
                                                success:
             ^(NSDictionary *receipt)
             {
                 [weakSelf restoreTransaction:transaction];
             }
                                                failure:
             ^(NSError *error)
             {
                 [weakSelf transactionFailed:transaction];
             }];
        } break;
            
        default:
            break;
    }    
}

- (void)completeTransaction:(SKPaymentTransaction *)transaction
{
    [self recordTransaction:transaction];
    [self.contentDelegate cargoManager:self provideContentForProductIdentifier:transaction.payment.productIdentifier];
    
    // Remove the transaction from the payment queue
    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
}

- (void)restoreTransaction:(SKPaymentTransaction *)transaction
{
    [self recordTransaction:transaction];
    [self.contentDelegate cargoManager:self provideContentForProductIdentifier:transaction.originalTransaction.payment.productIdentifier];
    
    // Remove the transaction from the payment queue
    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
}

- (void)transactionFailed:(SKPaymentTransaction *)transaction
{
    if (transaction.error.code != SKErrorPaymentCancelled) {
        
        // Display a transaction error here
#if TARGET_OS_IPHONE
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:transaction.error.localizedFailureReason
                                                        message:transaction.error.localizedDescription
                                                       delegate:nil
                                              cancelButtonTitle:CMAlertCancelButtonTitle
                                              otherButtonTitles:nil];
        [alert show];
#else
        NSWindow *window = [self.UIDelegate cargoManagerParentWindow:self];
        NSAlert *alert = [NSAlert alertWithError:transaction.error];
        [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
            return;
        }];
#endif
    }
    
    // Remove the transaction from the payment queue
    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
}

- (void)transactionRemoved:(SKPaymentTransaction *)transaction
{
    switch (transaction.transactionState) {
        case SKPaymentTransactionStatePurchased:
        case SKPaymentTransactionStateRestored:
            [self.UIDelegate cargoManager:self transactionDidFinishWithSuccess:YES];
            break;
            
        case SKPaymentTransactionStateFailed:
        default:
            [self.UIDelegate cargoManager:self transactionDidFinishWithSuccess:NO];
            break;
    }
}

- (void)recordTransaction:(SKPaymentTransaction *)transaction
{
    if ( _delegateFlags.recordTransaction ) {
        [self.contentDelegate cargoManager:self recordTransaction:transaction];
    }
}

- (void)restoredCompletedTransactionsWithError:(NSError *)error
{
    if ( _delegateFlags.restoredTransactionsDidFinishWithSuccess ) {
        [self.UIDelegate cargoManager:self restoredTransactionsDidFinishWithSuccess:( error == nil )];
    }
}

- (void)downloadUpdated:(SKDownload *)download
{
    if ( _delegateFlags.downloadUpdated ) {
        [self.contentDelegate cargoManager:self downloadUpdated:download];
    }
}

- (SKProduct *)productForIdentifier:(NSString *)identifier
{
    for (SKProduct *product in self.cachedProducts) {
        if ( [product.productIdentifier isEqualToString:identifier] ) {
            return product;
        }
    }
    
    return nil;
}

- (void)buyProduct:(SKProduct *)product
{
    if ([SKPaymentQueue canMakePayments]) {
        // Queue payment
        SKPayment *payment = [SKPayment paymentWithProduct:product];
        [[SKPaymentQueue defaultQueue] addPayment:payment];
    } else {
        [self showCannotMakePaymentsAlert];
    }
}

- (void)showCannotMakePaymentsAlert
{
    // Warn the user that purchases are disabled.
    // Display a transaction error here
#if TARGET_OS_IPHONE
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:CMCannotMakePaymentsAlertTitle
                                                    message:CMCannotMakePaymentsAlertMessage
                                                   delegate:nil
                                          cancelButtonTitle:CMAlertCancelButtonTitle
                                          otherButtonTitles:nil];
    [alert show];
#else
    NSWindow *window = [self.UIDelegate cargoManagerParentWindow:self];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.informativeText = CMCannotMakePaymentsAlertTitle;
    alert.messageText = CMCannotMakePaymentsAlertMessage;
    [alert addButtonWithTitle:CMAlertCancelButtonTitle];
    
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse returnCode) {
        return;
    }];
#endif
}

- (void)restorePurchasedProducts
{
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}

#pragma mark - Accessors
- (void)setContentDelegate:(id<CargoManagerContentDelegate>)contentDelegate
{
    if (_contentDelegate != contentDelegate) {
        _contentDelegate = contentDelegate;
        _delegateFlags.recordTransaction = [contentDelegate respondsToSelector:@selector(cargoManager:recordTransaction:)];
        _delegateFlags.downloadUpdated = [contentDelegate respondsToSelector:@selector(cargoManager:downloadUpdated:)];
    }
}

- (void)setUIDelegate:(id<CargoManagerUIDelegate>)UIDelegate
{
    if (_UIDelegate != UIDelegate) {
        _UIDelegate = UIDelegate;
        _delegateFlags.recordTransaction = [UIDelegate respondsToSelector:@selector(cargoManager:restoredTransactionsDidFinishWithSuccess:)];
    }
}

@end


@implementation SKProduct (LocalizedPrice)

- (NSString *)localizedPrice
{
    NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
    // Needed in case the default behaviour has been set elsewhere
    [numberFormatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
    [numberFormatter setNumberStyle:NSNumberFormatterCurrencyStyle];
    [numberFormatter setLocale:self.priceLocale];
    return [numberFormatter stringFromNumber:self.price];
}

@end
