//
//  CargoManager.h
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

#import <StoreKit/StoreKit.h>


extern NSString *const CMProductRequestDidReceiveResponseNotification;


@class SKProduct;
@protocol CargoManagerUIDelegate;
@protocol CargoManagerContentDelegate;


@interface CargoManager : NSObject

@property (nonatomic, readonly) BOOL isStoreLoaded;

@property (nonatomic, weak) id <CargoManagerContentDelegate>  contentDelegate;
@property (nonatomic, weak) id <CargoManagerUIDelegate>  UIDelegate;

+ (CargoManager *)sharedManager;

- (void)loadStore;

- (SKProduct *)productForIdentifier:(NSString *)identifier;

- (void)buyProduct:(SKProduct *)product;
- (void)restorePurchasedProducts;

@end


@protocol CargoManagerContentDelegate <NSObject>

// This method should return an array with all the productIdentifiers used by your App
- (NSArray *)cargoManagerProductIdentifiers:(CargoManager *)cargoManager;

// Implement this method to provide content
- (void)cargoManager:(CargoManager *)cargoManager provideContentForProductIdentifier:(NSString *)productIdentifier;

@optional

// Use this method if you want to store the transaction for your records
- (void)cargoManager:(CargoManager *)cargoManager recordTransaction:(SKPaymentTransaction *)transaction;

// Use this method to manage download data
- (void)cargoManager:(CargoManager *)cargoManager downloadUpdated:(SKDownload *)download;

@end


@protocol CargoManagerUIDelegate <NSObject>

#if TARGET_OS_MAC
- (NSWindow *)cargoManagerParentWindow:(CargoManager *)cargoManager;
#endif

// Implement this method to update UI after a IAP has finished
// This method is called both for successful and failed transactions
- (void)cargoManager:(CargoManager *)cargoManager transactionDidFinishWithSuccess:(BOOL)success;

@optional

// Implement this method to update UI after a IAP restore has finished
// This method is called both for successful and failed restores
- (void)cargoManager:(CargoManager *)cargoManager restoredTransactionsDidFinishWithSuccess:(BOOL)success;

@end


@interface SKProduct (LocalizedPrice)

@property (nonatomic, readonly) NSString *localizedPrice;

@end
