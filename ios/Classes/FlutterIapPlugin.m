#import "FlutterIapPlugin.h"
#import <StoreKit/StoreKit.h>


@interface FlutterIapPlugin () <SKProductsRequestDelegate, SKPaymentTransactionObserver, SKRequestDelegate, FlutterStreamHandler>
@property(nonatomic, retain) FlutterMethodChannel *channel;
@property(nonatomic, retain) FlutterEventChannel *stream;
@property(nonatomic, copy) FlutterEventSink eventSink;
@property(nonatomic, copy) FlutterResult productResult;
@property(nonatomic, copy) FlutterResult paymentResult;
@property(nonatomic, copy) FlutterResult subscriptionValidResult;
@property(nonatomic, retain) NSString *sharedSecret;
@property(nonatomic, retain) NSMutableDictionary *products;
@property(nonatomic, retain) NSMutableDictionary *transactionProducts;
@property(nonatomic, retain) NSMutableDictionary *transactions;
@property (assign, nonatomic) BOOL               flutterListening;
@end


@implementation FlutterIapPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    FlutterIapPlugin *instance = [[FlutterIapPlugin alloc] init];
    instance.channel =
        [FlutterMethodChannel methodChannelWithName:@"flutter_iap"
                                binaryMessenger:[registrar messenger]];
    instance.stream = [FlutterEventChannel eventChannelWithName: @"flutter_iap_stream"
                                binaryMessenger:[registrar messenger]];
    [registrar addMethodCallDelegate:instance channel:instance.channel];
    [instance.stream setStreamHandler:instance];
}


- (instancetype)init {
    self = [super init];
    self.products = [[NSMutableDictionary alloc] init];
    self.transactions = [[NSMutableDictionary alloc] init];
    self.transactionProducts = [[NSMutableDictionary alloc] init];
    [[SKPaymentQueue defaultQueue] addTransactionObserver: self];
    return self;
}

- (void)dealloc {
    [self.channel setMethodCallHandler:nil];
    if ([SKPaymentQueue canMakePayments]) {
            [[SKPaymentQueue defaultQueue] removeTransactionObserver:self];
    }
    self.channel = nil;
}

- (void)fetchProduct:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSSet *data = [NSSet setWithArray:call.arguments];
    NSLog(@"Send Fetch Product %@", data);
    SKProductsRequest *req = [[SKProductsRequest alloc] initWithProductIdentifiers: data];
    req.delegate = self;
    self.productResult = result;
    [req start];
}

- (void)buyProduct:(FlutterMethodCall *)call result:(FlutterResult)result {
    if([SKPaymentQueue canMakePayments]) {
        NSString *productid = call.arguments;
        SKProduct *product = [self.products objectForKey:productid];
        if(product != nil) {
            SKMutablePayment *payment = [SKMutablePayment paymentWithProduct:product];
            payment.quantity = 1;
            NSString *transactionId = [[NSProcessInfo processInfo] globallyUniqueString];
            [self.transactionProducts setObject:payment forKey:transactionId];
            result( transactionId );
            NSMutableArray *items = [[NSMutableArray alloc] init];
            for(SKPaymentTransaction *trans in [SKPaymentQueue defaultQueue].transactions) {
                if( [productid isEqualToString: trans.payment.productIdentifier] ) {
                   // [[SKPaymentQueue defaultQueue]  finishTransaction:trans];
                    [items addObject:trans];
                }
            }
            if([items count] > 0) {
                [self paymentQueue:[SKPaymentQueue defaultQueue] updatedTransactions:items];
                NSLog(@"Already pending transactions %lu", [items count]);
            }else{
                [[SKPaymentQueue defaultQueue] addPayment:payment];
            }
        }else{
            result( @"error: badproduct" );
        }
    }else{
        result( @"error:disabled" );
    }
}


- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    if ([call.method isEqualToString:@"fetch"]) {
        [self fetchProduct:call result:result];
        return;
    }
    
    if ([call.method isEqualToString:@"buy"]) {
        [self buyProduct:call result:result];
        return;
    }

    if ([call.method isEqualToString:@"getTransactions"]) {
        result( self.transactions );
        return;
    }
    
    if ([call.method isEqualToString:@"getTransaction"]) {
        result( [self.transactions objectForKey:call.arguments] );
        return;
    }
    
    if ([call.method isEqualToString:@"subscriptionValid"]) {
        NSString *sharedSecret = (NSString*)call.arguments;
        [self checkInAppPurchaseStatus:sharedSecret result:result];
        return;
    }
    
    result(FlutterMethodNotImplemented);
}




- (void)productsRequest:(nonnull SKProductsRequest *)request didReceiveResponse:(nonnull SKProductsResponse *)response {
    NSMutableDictionary *ret = [[NSMutableDictionary alloc] init];
    [self.products removeAllObjects];
    for(SKProduct *product in response.products) {
        NSLog(@"PRODUCT ID %@", product.productIdentifier);
        NSString *subUnits = @"";
        NSString *subQuamtity = @"";
        [self.products setObject:product forKey:product.productIdentifier];
        if( @available(iOS 11.2, *) ) {
            if ( product.subscriptionPeriod != nil) {
                switch( product.subscriptionPeriod.unit ) {
                    case SKProductPeriodUnitDay:
                        subUnits = @"day";
                        break;
                    case SKProductPeriodUnitWeek:
                        subUnits = @"week";
                        break;
                    case SKProductPeriodUnitMonth:
                        subUnits = @"month";
                        break;
                    case SKProductPeriodUnitYear:
                        subUnits = @"year";
                        break;
                }
                subQuamtity = [NSString stringWithFormat: @"%ld", (long)product.subscriptionPeriod.numberOfUnits ];
            }
        }
        
        NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
        [formatter setLocale: product.priceLocale];
        [formatter setNumberStyle:NSNumberFormatterCurrencyStyle];
        
        
        ret[ product.productIdentifier ] = @{
             @"description": product.localizedDescription,
             @"title": product.localizedTitle,
             @"price": product.price.stringValue,
             @"localPrice": [formatter stringFromNumber:product.price],
             @"subscriptionUnit": subUnits,
             @"subscriptionQuantity": subQuamtity
        };
    }
    NSLog(@"Got Product result %@", ret);
    if( self.productResult != nil) {
        self.productResult( ret );
        self.productResult = nil;
    }
}

- (void)paymentQueue:(nonnull SKPaymentQueue *)queue updatedTransactions:(nonnull NSArray<SKPaymentTransaction *> *)transactions {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    bool valid = false;
    for(SKPaymentTransaction *trans in transactions) {
        NSString *transactionId = nil;
        for(NSString *tid in self.transactionProducts) {
            SKPayment *payment = [self.transactionProducts objectForKey:tid];
            if( [payment.productIdentifier isEqualToString: trans.payment.productIdentifier] ) {
                transactionId = tid;
                break;
            }
        }
        if(transactionId == nil) {
            NSLog(@"Unable to find transaction id");
            continue;
        }
        NSString *productId = trans.payment.productIdentifier;
        NSLog(@"productId %@", productId);
        NSMutableDictionary *v = [[NSMutableDictionary alloc] init];
        [v setObject:productId forKey:@"productId"];
        if( trans.transactionDate != nil) {
            [v setObject:[formatter stringFromDate: trans.transactionDate] forKey:@"date"];
        }
        NSLog(@"transactions %@", productId);
        switch(trans.transactionState) {
            case SKPaymentTransactionStatePurchasing:
                [v setObject:@"Purchasing" forKey:@"state"];
                NSLog(@"Purchasing");
                break;
            case SKPaymentTransactionStatePurchased:
                [v setObject:@"Purchased" forKey:@"state"];
                NSLog(@"Purchased");
                [queue finishTransaction:trans];
                break;
            case SKPaymentTransactionStateFailed:
                [v setObject:@"Failed" forKey:@"state"];
                [v setObject:trans.error.localizedDescription forKey:@"error"];
                NSLog(@"Failed %@", trans.error);
                [queue  finishTransaction:trans];
                break;
            case SKPaymentTransactionStateRestored:
                [v setObject:@"Restored" forKey:@"state"];
                NSLog(@"Restored");
                [queue finishTransaction:trans];
                break;
            case SKPaymentTransactionStateDeferred:
                [v setObject:@"Defered" forKey:@"state"];
                NSLog(@"Defered");
                break;
        }
        if(trans.transactionIdentifier) {
            [v setObject:trans.transactionIdentifier forKey:@"transactionIdentifier"];
        }
        NSLog(@"transactionid %@ %@", transactionId,v);
        [self.transactions setObject:v forKey:transactionId];
        valid = true;
    }
    /*
    if( valid && self.paymentResult != nil) {
        self.paymentResult( self.transactions );
        self.paymentResult = nil;
    }*/
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error {
    NSLog(@"Failed to load list of products %@", error);
}

- (void)checkInAppPurchaseStatus:(NSString*)sharedSecret result:(FlutterResult)result
{
    // Load the receipt from the app bundle.
    NSURL *receiptURL = [[NSBundle mainBundle] appStoreReceiptURL];
    NSLog(@"URL %@", receiptURL.absoluteString);
    NSData *receipt = [NSData dataWithContentsOfURL:receiptURL];
    if (receipt) {
        BOOL sandbox = [[receiptURL lastPathComponent] isEqualToString:@"sandboxReceipt"];
        // Create the JSON object that describes the request
        NSError *error;
        NSDictionary *requestContents = @{
                                          @"receipt-data": [receipt base64EncodedStringWithOptions:0],@"password":sharedSecret
                                          };
        NSData *requestData = [NSJSONSerialization dataWithJSONObject:requestContents
                                                              options:0
                                                                error:&error];
        
        if (requestData) {
            // Create a POST request with the receipt data.
            NSURL *storeURL = [NSURL URLWithString:@"https://buy.itunes.apple.com/verifyReceipt"];
            if (sandbox) {
                storeURL = [NSURL URLWithString:@"https://sandbox.itunes.apple.com/verifyReceipt"];
            }
            NSURLSession *session = [NSURLSession sharedSession];
            NSMutableURLRequest *storeRequest = [NSMutableURLRequest requestWithURL:storeURL
                                                                   cachePolicy:NSURLRequestUseProtocolCachePolicy
                                                               timeoutInterval:60.0];
            [storeRequest setHTTPMethod:@"POST"];
            [storeRequest setHTTPBody:requestData];
            NSURLSessionDataTask *task = [session dataTaskWithRequest:storeRequest
                    completionHandler:^(NSData *resData,
                                        NSURLResponse *response,
                                        NSError *error) {
                        // handle response
                        
                        
                        NSString *rs = @"NO";
                        //Can use sendAsynchronousRequest to request to Apple API, here I use sendSynchronousRequest
                        NSString *strData = [[NSString alloc]initWithData:resData encoding:NSUTF8StringEncoding];
                        NSLog(@"%@", strData);
                        if (error) {
                            NSLog(@"Receipt Validation failed" );
                            
                            rs = @"NO";
                        }
                        else
                        {
                            NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:resData options:0 error:&error];
                            if (!jsonResponse) {
                                NSLog(@"Receipt invalid json");
                                rs = @"NO";
                            }
                            else
                            {
                                NSLog(@"jsonResponse:%@", jsonResponse);
                                
                                NSDictionary *dictLatestReceiptsInfo = jsonResponse[@"latest_receipt_info"];
                                long long int expirationDateMs = [[dictLatestReceiptsInfo valueForKeyPath:@"@max.expires_date_ms"] longLongValue];
                                long long requestDateMs = [jsonResponse[@"receipt"][@"request_date_ms"] longLongValue];
                                NSLog(@"%lld--%lld", expirationDateMs, requestDateMs);
                                bool valid = [[jsonResponse objectForKey:@"status"] integerValue] == 0 && (expirationDateMs > requestDateMs);
                                if( valid ) {
                                    rs = [NSString stringWithFormat:@"YES,%lld", expirationDateMs ];
                                }else{
                                    NSLog(@"Subscription expired");
                                }
                            }
                        }
                        result( rs );
            }];
            [task resume];
        }
        else
        {
            NSLog(@"Request data empty" );
            
            result( @"NO" );
        }
    }
    else
    {
        NSLog(@"Refresh Receipt");
        
        SKReceiptRefreshRequest *refreshReceiptRequest = [[SKReceiptRefreshRequest alloc] initWithReceiptProperties:nil];
        refreshReceiptRequest.delegate = self;
        self.subscriptionValidResult = result;
        self.sharedSecret = sharedSecret;
        [refreshReceiptRequest start];
        
    }
}

- (void)requestDidFinish:(SKRequest *)request {
    if([request isKindOfClass:[SKReceiptRefreshRequest class]])
    {
        NSLog(@"App Receipt exists after refresh");
        NSURL *receiptURL = [[NSBundle mainBundle] appStoreReceiptURL];
        NSData *receipt = [NSData dataWithContentsOfURL:receiptURL];
        if (receipt && self.subscriptionValidResult!=nil) {
            [self checkInAppPurchaseStatus:self.sharedSecret result:self.subscriptionValidResult];
        }
    } else if([request isKindOfClass:[SKProductsRequest class]]) {
        return;
    } else {
        NSLog(@"Receipt request done but there is no receipt %@", request);
    }
}

- (FlutterError * _Nullable)onCancelWithArguments:(id _Nullable)arguments {
    self.eventSink = NULL;
    self.flutterListening = NO;
    return nil;
}

- (FlutterError * _Nullable)onListenWithArguments:(id _Nullable)arguments eventSink:(nonnull FlutterEventSink)events {
    self.eventSink = events;
    self.flutterListening = YES;
    return nil;
}

@end






/*
 
 {
 "status": 0,
 "environment": "Sandbox",
 "receipt": {
 "receipt_type": "ProductionSandbox",
 "adam_id": 0,
 "app_item_id": 0,
 "bundle_id": "com.arcinternet.raildarapp",
 "application_version": "1",
 "download_id": 0,
 "version_external_identifier": 0,
 "receipt_creation_date": "2018-03-19 20:04:09 Etc\/GMT",
 "receipt_creation_date_ms": "1521489849000",
 "receipt_creation_date_pst": "2018-03-19 13:04:09 America\/Los_Angeles",
 "request_date": "2018-03-19 20:04:22 Etc\/GMT",
 "request_date_ms": "1521489862272",
 "request_date_pst": "2018-03-19 13:04:22 America\/Los_Angeles",
 "original_purchase_date": "2013-08-01 07:00:00 Etc\/GMT",
 "original_purchase_date_ms": "1375340400000",
 "original_purchase_date_pst": "2013-08-01 00:00:00 America\/Los_Angeles",
 "original_application_version": "1.0",
 "in_app": [
 {
 "quantity": "1",
 "product_id": "raildar6month",
 "transaction_id": "1000000383586477",
 "original_transaction_id": "1000000383586477",
 "purchase_date": "2018-03-18 21:24:25 Etc\/GMT",
 "purchase_date_ms": "1521408265000",
 "purchase_date_pst": "2018-03-18 14:24:25 America\/Los_Angeles",
 "original_purchase_date": "2018-03-18 21:24:28 Etc\/GMT",
 "original_purchase_date_ms": "1521408268000",
 "original_purchase_date_pst": "2018-03-18 14:24:28 America\/Los_Angeles",
 "expires_date": "2018-03-18 21:54:25 Etc\/GMT",
 "expires_date_ms": "1521410065000",
 "expires_date_pst": "2018-03-18 14:54:25 America\/Los_Angeles",
 "web_order_line_item_id": "1000000038146560",
 "is_trial_period": "false",
 "is_in_intro_offer_period": "false"
 },
 {
 "quantity": "1",
 "product_id": "raildar6month",
 "transaction_id": "1000000383587704",
 "original_transaction_id": "1000000383586477",
 "purchase_date": "2018-03-18 21:54:25 Etc\/GMT",
 "purchase_date_ms": "1521410065000",
 "purchase_date_pst": "2018-03-18 14:54:25 America\/Los_Angeles",
 "original_purchase_date": "2018-03-18 21:24:28 Etc\/GMT",
 "original_purchase_date_ms": "1521408268000",
 "original_purchase_date_pst": "2018-03-18 14:24:28 America\/Los_Angeles",
 "expires_date": "2018-03-18 22:24:25 Etc\/GMT",
 "expires_date_ms": "1521411865000",
 "expires_date_pst": "2018-03-18 15:24:25 America\/Los_Angeles",
 "web_order_line_item_id": "1000000038146561",
 "is_trial_period": "false",
 "is_in_intro_offer_period": "false"
 },
 {
 "quantity": "1",
 "product_id": "raildar6month",
 "transaction_id": "1000000383588468",
 "original_transaction_id": "1000000383586477",
 "purchase_date": "2018-03-18 22:24:25 Etc\/GMT",
 "purchase_date_ms": "1521411865000",
 "purchase_date_pst": "2018-03-18 15:24:25 America\/Los_Angeles",
 "original_purchase_date": "2018-03-18 21:24:28 Etc\/GMT",
 "original_purchase_date_ms": "1521408268000",
 "original_purchase_date_pst": "2018-03-18 14:24:28 America\/Los_Angeles",
 "expires_date": "2018-03-18 22:54:25 Etc\/GMT",
 "expires_date_ms": "1521413665000",
 "expires_date_pst": "2018-03-18 15:54:25 America\/Los_Angeles",
 "web_order_line_item_id": "1000000038146623",
 "is_trial_period": "false",
 "is_in_intro_offer_period": "false"
 },
 {
 "quantity": "1",
 "product_id": "raildar6month",
 "transaction_id": "1000000383589210",
 "original_transaction_id": "1000000383586477",
 "purchase_date": "2018-03-18 22:54:25 Etc\/GMT",
 "purchase_date_ms": "1521413665000",
 "purchase_date_pst": "2018-03-18 15:54:25 America\/Los_Angeles",
 "original_purchase_date": "2018-03-18 21:24:28 Etc\/GMT",
 "original_purchase_date_ms": "1521408268000",
 "original_purchase_date_pst": "2018-03-18 14:24:28 America\/Los_Angeles",
 "expires_date": "2018-03-18 23:24:25 Etc\/GMT",
 "expires_date_ms": "1521415465000",
 "expires_date_pst": "2018-03-18 16:24:25 America\/Los_Angeles",
 "web_order_line_item_id": "1000000038146671",
 "is_trial_period": "false",
 "is_in_intro_offer_period": "false"
 },
 {
 "quantity": "1",
 "product_id": "raildar6month",
 "transaction_id": "1000000383589369",
 "original_transaction_id": "1000000383586477",
 "purchase_date": "2018-03-18 23:24:25 Etc\/GMT",
 "purchase_date_ms": "1521415465000",
 "purchase_date_pst": "2018-03-18 16:24:25 America\/Los_Angeles",
 "original_purchase_date": "2018-03-18 21:24:28 Etc\/GMT",
 "original_purchase_date_ms": "1521408268000",
 "original_purchase_date_pst": "2018-03-18 14:24:28 America\/Los_Angeles",
 "expires_date": "2018-03-18 23:54:25 Etc\/GMT",
 "expires_date_ms": "1521417265000",
 "expires_date_pst": "2018-03-18 16:54:25 America\/Los_Angeles",
 "web_order_line_item_id": "1000000038146736",
 "is_trial_period": "false",
 "is_in_intro_offer_period": "false"
 },
 {
 "quantity": "1",
 "product_id": "raildar6month",
 "transaction_id": "1000000383589625",
 "original_transaction_id": "1000000383586477",
 "purchase_date": "2018-03-18 23:54:25 Etc\/GMT",
 "purchase_date_ms": "1521417265000",
 "purchase_date_pst": "2018-03-18 16:54:25 America\/Los_Angeles",
 "original_purchase_date": "2018-03-18 21:24:28 Etc\/GMT",
 "original_purchase_date_ms": "1521408268000",
 "original_purchase_date_pst": "2018-03-18 14:24:28 America\/Los_Angeles",
 "expires_date": "2018-03-19 00:24:25 Etc\/GMT",
 "expires_date_ms": "1521419065000",
 "expires_date_pst": "2018-03-18 17:24:25 America\/Los_Angeles",
 "web_order_line_item_id": "1000000038146808",
 "is_trial_period": "false",
 "is_in_intro_offer_period": "false"
 }
 ]
 },
 "latest_receipt_info": [
 {
 "quantity": "1",
 "product_id": "raildar6month",
 "transaction_id": "1000000383586477",
 "original_transaction_id": "1000000383586477",
 "purchase_date": "2018-03-18 21:24:25 Etc\/GMT",
 "purchase_date_ms": "1521408265000",
 "purchase_date_pst": "2018-03-18 14:24:25 America\/Los_Angeles",
 "original_purchase_date": "2018-03-18 21:24:28 Etc\/GMT",
 "original_purchase_date_ms": "1521408268000",
 "original_purchase_date_pst": "2018-03-18 14:24:28 America\/Los_Angeles",
 "expires_date": "2018-03-18 21:54:25 Etc\/GMT",
 "expires_date_ms": "1521410065000",
 "expires_date_pst": "2018-03-18 14:54:25 America\/Los_Angeles",
 "web_order_line_item_id": "1000000038146560",
 "is_trial_period": "false",
 "is_in_intro_offer_period": "false"
 },
 {
 "quantity": "1",
 "product_id": "raildar6month",
 "transaction_id": "1000000383587704",
 "original_transaction_id": "1000000383586477",
 "purchase_date": "2018-03-18 21:54:25 Etc\/GMT",
 "purchase_date_ms": "1521410065000",
 "purchase_date_pst": "2018-03-18 14:54:25 America\/Los_Angeles",
 "original_purchase_date": "2018-03-18 21:24:28 Etc\/GMT",
 "original_purchase_date_ms": "1521408268000",
 "original_purchase_date_pst": "2018-03-18 14:24:28 America\/Los_Angeles",
 "expires_date": "2018-03-18 22:24:25 Etc\/GMT",
 "expires_date_ms": "1521411865000",
 "expires_date_pst": "2018-03-18 15:24:25 America\/Los_Angeles",
 "web_order_line_item_id": "1000000038146561",
 "is_trial_period": "false",
 "is_in_intro_offer_period": "false"
 },
 {
 "quantity": "1",
 "product_id": "raildar6month",
 "transaction_id": "1000000383588468",
 "original_transaction_id": "1000000383586477",
 "purchase_date": "2018-03-18 22:24:25 Etc\/GMT",
 "purchase_date_ms": "1521411865000",
 "purchase_date_pst": "2018-03-18 15:24:25 America\/Los_Angeles",
 "original_purchase_date": "2018-03-18 21:24:28 Etc\/GMT",
 "original_purchase_date_ms": "1521408268000",
 "original_purchase_date_pst": "2018-03-18 14:24:28 America\/Los_Angeles",
 "expires_date": "2018-03-18 22:54:25 Etc\/GMT",
 "expires_date_ms": "1521413665000",
 "expires_date_pst": "2018-03-18 15:54:25 America\/Los_Angeles",
 "web_order_line_item_id": "1000000038146623",
 "is_trial_period": "false",
 "is_in_intro_offer_period": "false"
 },
 {
 "quantity": "1",
 "product_id": "raildar6month",
 "transaction_id": "1000000383589210",
 "original_transaction_id": "1000000383586477",
 "purchase_date": "2018-03-18 22:54:25 Etc\/GMT",
 "purchase_date_ms": "1521413665000",
 "purchase_date_pst": "2018-03-18 15:54:25 America\/Los_Angeles",
 "original_purchase_date": "2018-03-18 21:24:28 Etc\/GMT",
 "original_purchase_date_ms": "1521408268000",
 "original_purchase_date_pst": "2018-03-18 14:24:28 America\/Los_Angeles",
 "expires_date": "2018-03-18 23:24:25 Etc\/GMT",
 "expires_date_ms": "1521415465000",
 "expires_date_pst": "2018-03-18 16:24:25 America\/Los_Angeles",
 "web_order_line_item_id": "1000000038146671",
 "is_trial_period": "false",
 "is_in_intro_offer_period": "false"
 },
 {
 "quantity": "1",
 "product_id": "raildar6month",
 "transaction_id": "1000000383589369",
 "original_transaction_id": "1000000383586477",
 "purchase_date": "2018-03-18 23:24:25 Etc\/GMT",
 "purchase_date_ms": "1521415465000",
 "purchase_date_pst": "2018-03-18 16:24:25 America\/Los_Angeles",
 "original_purchase_date": "2018-03-18 21:24:28 Etc\/GMT",
 "original_purchase_date_ms": "1521408268000",
 "original_purchase_date_pst": "2018-03-18 14:24:28 America\/Los_Angeles",
 "expires_date": "2018-03-18 23:54:25 Etc\/GMT",
 "expires_date_ms": "1521417265000",
 "expires_date_pst": "2018-03-18 16:54:25 America\/Los_Angeles",
 "web_order_line_item_id": "1000000038146736",
 "is_trial_period": "false",
 "is_in_intro_offer_period": "false"
 },
 {
 "quantity": "1",
 "product_id": "raildar6month",
 "transaction_id": "1000000383589625",
 "original_transaction_id": "1000000383586477",
 "purchase_date": "2018-03-18 23:54:25 Etc\/GMT",
 "purchase_date_ms": "1521417265000",
 "purchase_date_pst": "2018-03-18 16:54:25 America\/Los_Angeles",
 "original_purchase_date": "2018-03-18 21:24:28 Etc\/GMT",
 "original_purchase_date_ms": "1521408268000",
 "original_purchase_date_pst": "2018-03-18 14:24:28 America\/Los_Angeles",
 "expires_date": "2018-03-19 00:24:25 Etc\/GMT",
 "expires_date_ms": "1521419065000",
 "expires_date_pst": "2018-03-18 17:24:25 America\/Los_Angeles",
 "web_order_line_item_id": "1000000038146808",
 "is_trial_period": "false",
 "is_in_intro_offer_period": "false"
 }
 ],
 "latest_receipt": "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\/Qrk8H9Pm\/KwfU8qY9SGsAlCnYO3v6Z\/v\/Ca\/VbXqxzUUkIVonMQ5DMjoEC0KCXtlyxoWlph5AQaCYmObgdEHOwCl3Fc9DfdjvYLdmIHuPsB8\/ijtDT+iZVge\/iA0kjAgMBAAGjggHXMIIB0zA\/BggrBgEFBQcBAQQzMDEwLwYIKwYBBQUHMAGGI2h0dHA6Ly9vY3NwLmFwcGxlLmNvbS9vY3NwMDMtd3dkcjA0MB0GA1UdDgQWBBSRpJz8xHa3n6CK9E31jzZd7SsEhTAMBgNVHRMBAf8EAjAAMB8GA1UdIwQYMBaAFIgnFwmpthhgi+zruvZHWcVSVKO3MIIBHgYDVR0gBIIBFTCCAREwggENBgoqhkiG92NkBQYBMIH+MIHDBggrBgEFBQcCAjCBtgyBs1JlbGlhbmNlIG9uIHRoaXMgY2VydGlmaWNhdGUgYnkgYW55IHBhcnR5IGFzc3VtZXMgYWNjZXB0YW5jZSBvZiB0aGUgdGhlbiBhcHBsaWNhYmxlIHN0YW5kYXJkIHRlcm1zIGFuZCBjb25kaXRpb25zIG9mIHVzZSwgY2VydGlmaWNhdGUgcG9saWN5IGFuZCBjZXJ0aWZpY2F0aW9uIHByYWN0aWNlIHN0YXRlbWVudHMuMDYGCCsGAQUFBwIBFipodHRwOi8vd3d3LmFwcGxlLmNvbS9jZXJ0aWZpY2F0ZWF1dGhvcml0eS8wDgYDVR0PAQH\/BAQDAgeAMBAGCiqGSIb3Y2QGCwEEAgUAMA0GCSqGSIb3DQEBBQUAA4IBAQANphvTLj3jWysHbkKWbNPojEMwgl\/gXNGNvr0PvRr8JZLbjIXDgFnf4+LXLgUUrA3btrj+\/DUufMutF2uOfx\/kd7mxZ5W0E16mGYZ2+FogledjjA9z\/Ojtxh+umfhlSFyg4Cg6wBA3LbmgBDkfc7nIBf3y3n8aKipuKwH8oCBc2et9J6Yz+PWY4L5E27FMZ\/xuCk\/J4gao0pfzp45rUaJahHVl0RYEYuPBX\/UIqc9o2ZIAycGMs\/iNAGS6WGDAfK+PdcppuVsq1h1obphC9UynNxmbzDscehlD86Ntv0hgBgw2kivs3hi1EdotI9CO\/KBpnBcbnoB7OUdFMGEvxxOoMIIEIjCCAwqgAwIBAgIIAd68xDltoBAwDQYJKoZIhvcNAQEFBQAwYjELMAkGA1UEBhMCVVMxEzARBgNVBAoTCkFwcGxlIEluYy4xJjAkBgNVBAsTHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRYwFAYDVQQDEw1BcHBsZSBSb290IENBMB4XDTEzMDIwNzIxNDg0N1oXDTIzMDIwNzIxNDg0N1owgZYxCzAJBgNVBAYTAlVTMRMwEQYDVQQKDApBcHBsZSBJbmMuMSwwKgYDVQQLDCNBcHBsZSBXb3JsZHdpZGUgRGV2ZWxvcGVyIFJlbGF0aW9uczFEMEIGA1UEAww7QXBwbGUgV29ybGR3aWRlIERldmVsb3BlciBSZWxhdGlvbnMgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDKOFSmy1aqyCQ5SOmM7uxfuH8mkbw0U3rOfGOAYXdkXqUHI7Y5\/lAtFVZYcC1+xG7BSoU+L\/DehBqhV8mvexj\/avoVEkkVCBmsqtsqMu2WY2hSFT2Miuy\/axiV4AOsAX2XBWfODoWVN2rtCbauZ81RZJ\/GXNG8V25nNYB2NqSHgW44j9grFU57Jdhav06DwY3Sk9UacbVgnJ0zTlX5ElgMhrgWDcHld0WNUEi6Ky3klIXh6MSdxmilsKP8Z35wugJZS3dCkTm59c3hTO\/AO0iMpuUhXf1qarunFjVg0uat80YpyejDi+l5wGphZxWy8P3laLxiX27Pmd3vG2P+kmWrAgMBAAGjgaYwgaMwHQYDVR0OBBYEFIgnFwmpthhgi+zruvZHWcVSVKO3MA8GA1UdEwEB\/wQFMAMBAf8wHwYDVR0jBBgwFoAUK9BpR5R2Cf70a40uQKb3R01\/CF4wLgYDVR0fBCcwJTAjoCGgH4YdaHR0cDovL2NybC5hcHBsZS5jb20vcm9vdC5jcmwwDgYDVR0PAQH\/BAQDAgGGMBAGCiqGSIb3Y2QGAgEEAgUAMA0GCSqGSIb3DQEBBQUAA4IBAQBPz+9Zviz1smwvj+4ThzLoBTWobot9yWkMudkXvHcs1Gfi\/ZptOllc34MBvbKuKmFysa\/Nw0Uwj6ODDc4dR7Txk4qjdJukw5hyhzs+r0ULklS5MruQGFNrCk4QttkdUGwhgAqJTleMa1s8Pab93vcNIx0LSiaHP7qRkkykGRIZbVf1eliHe2iK5IaMSuviSRSqpd1VAKmuu0swruGgsbwpgOYJd+W+NKIByn\/c4grmO7i77LpilfMFY0GCzQ87HUyVpNur+cmV6U\/kTecmmYHpvPm0KdIBembhLoz2IYrF+Hjhga6\/05Cdqa3zr\/04GpZnMBxRpVzscYqCtGwPDBUfMIIEuzCCA6OgAwIBAgIBAjANBgkqhkiG9w0BAQUFADBiMQswCQYDVQQGEwJVUzETMBEGA1UEChMKQXBwbGUgSW5jLjEmMCQGA1UECxMdQXBwbGUgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkxFjAUBgNVBAMTDUFwcGxlIFJvb3QgQ0EwHhcNMDYwNDI1MjE0MDM2WhcNMzUwMjA5MjE0MDM2WjBiMQswCQYDVQQGEwJVUzETMBEGA1UEChMKQXBwbGUgSW5jLjEmMCQGA1UECxMdQXBwbGUgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkxFjAUBgNVBAMTDUFwcGxlIFJvb3QgQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDkkakJH5HbHkdQ6wXtXnmELes2oldMVeyLGYne+Uts9QerIjAC6Bg++FAJ039BqJj50cpmnCRrEdCju+QbKsMflZ56DKRHi1vUFjczy8QPTc4UadHJGXL1XQ7Vf1+b8iUDulWPTV0N8WQ1IxVLFVkds5T39pyez1C6wVhQZ48ItCD3y6wsIG9wtj8BMIy3Q88PnT3zK0koGsj+zrW5DtleHNbLPbU6rfQPDgCSC7EhFi501TwN22IWq6NxkkdTVcGvL0Gz+PvjcM3mo0xFfh9Ma1CWQYnEdGILEINBhzOKgbEwWOxaBDKMaLOPHd5lc\/9nXmW8Sdh2nzMUZaF3lMktAgMBAAGjggF6MIIBdjAOBgNVHQ8BAf8EBAMCAQYwDwYDVR0TAQH\/BAUwAwEB\/zAdBgNVHQ4EFgQUK9BpR5R2Cf70a40uQKb3R01\/CF4wHwYDVR0jBBgwFoAUK9BpR5R2Cf70a40uQKb3R01\/CF4wggERBgNVHSAEggEIMIIBBDCCAQAGCSqGSIb3Y2QFATCB8jAqBggrBgEFBQcCARYeaHR0cHM6Ly93d3cuYXBwbGUuY29tL2FwcGxlY2EvMIHDBggrBgEFBQcCAjCBthqBs1JlbGlhbmNlIG9uIHRoaXMgY2VydGlmaWNhdGUgYnkgYW55IHBhcnR5IGFzc3VtZXMgYWNjZXB0YW5jZSBvZiB0aGUgdGhlbiBhcHBsaWNhYmxlIHN0YW5kYXJkIHRlcm1zIGFuZCBjb25kaXRpb25zIG9mIHVzZSwgY2VydGlmaWNhdGUgcG9saWN5IGFuZCBjZXJ0aWZpY2F0aW9uIHByYWN0aWNlIHN0YXRlbWVudHMuMA0GCSqGSIb3DQEBBQUAA4IBAQBcNplMLXi37Yyb3PN3m\/J20ncwT8EfhYOFG5k9RzfyqZtAjizUsZAS2L70c5vu0mQPy3lPNNiiPvl4\/2vIB+x9OYOLUyDTOMSxv5pPCmv\/K\/xZpwUJfBdAVhEedNO3iyM7R6PVbyTi69G3cN8PReEnyvFteO3ntRcXqNx+IjXKJdXZD9Zr1KIkIxH3oayPc4FgxhtbCS+SsvhESPBgOJ4V9T0mZyCKM2r3DYLP3uujL\/lTaltkwGMzd\/c6ByxW69oPIQ7aunMZT7XZNn\/Bh1XZp5m5MkL72NVxnn6hUrcbvZNCJBIqxw8dtk2cXmPIS4AXUKqK1drk\/NAJBzewdXUhMYIByzCCAccCAQEwgaMwgZYxCzAJBgNVBAYTAlVTMRMwEQYDVQQKDApBcHBsZSBJbmMuMSwwKgYDVQQLDCNBcHBsZSBXb3JsZHdpZGUgRGV2ZWxvcGVyIFJlbGF0aW9uczFEMEIGA1UEAww7QXBwbGUgV29ybGR3aWRlIERldmVsb3BlciBSZWxhdGlvbnMgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkCCA7rV4fnngmNMAkGBSsOAwIaBQAwDQYJKoZIhvcNAQEBBQAEggEAkgmBr0AGwqvgf3v4E92vgjvdP6k\/4Fj73yKL+1rGaDSY1yF2bD\/Lp5aeHCajAQBL8chbWKhi6A8l99ZIgZdirPP2WCjJ9\/MjBiI9o9teU0+l6GjBD00UrTIgzksO0KXyKtMQEwVtIqm9dkYQPfC7jx621+QZf3cXzlTUmrHK2JaCGIMb0DKG\/9a7gdjoBH+yFgQlxQxzPIr4HVrQKLEOvimoDNqy\/Kr1NQB710mmdJnpj0wC2W4ak2BbMTmCGe3LGA+A80WaL3HUf\/3\/WJ0liSIR0Pc+QmVdE2mMBoSMv96VzI6Pi92Z2ryqSjDUUYjqcITq5cg7UbRs9HUkkxtCMw==",
 "pending_renewal_info": [
 {
 "expiration_intent": "1",
 "auto_renew_product_id": "raildar6month",
 "original_transaction_id": "1000000383586477",
 "is_in_billing_retry_period": "0",
 "product_id": "raildar6month",
 "auto_renew_status": "0"
 }
 ]
 }
 */
 
