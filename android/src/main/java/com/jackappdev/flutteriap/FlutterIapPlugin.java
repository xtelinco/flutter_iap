package com.jackappdev.flutteriap;

import android.app.Activity;
import android.app.Application;
import android.content.Intent;
import android.os.Bundle;
import android.support.annotation.Nullable;
import android.util.Log;

import com.android.billingclient.api.BillingClient;
import com.android.billingclient.api.BillingClient.BillingResponse;
import com.android.billingclient.api.Purchase;
import com.android.billingclient.api.BillingClient.SkuType;
import com.android.billingclient.api.SkuDetails;
import com.android.billingclient.api.SkuDetailsParams;
import com.android.billingclient.api.SkuDetailsResponseListener;


import java.util.List;
import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;
import java.util.HashMap;
import java.util.Date;
import java.text.SimpleDateFormat;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry;
import io.flutter.plugin.common.PluginRegistry.Registrar;

/**
 * FlutterIapPlugin
 */
public class FlutterIapPlugin implements MethodCallHandler {
    private final Activity activity;
    private BillingManager billingManager;
    private Map<String, Purchase> storedPurchases;

    public static void registerWith(Registrar registrar) {
        if( registrar.activity() == null) {
            return;
        }
        final MethodChannel channel = new MethodChannel(registrar.messenger(), "flutter_iap");
        channel.setMethodCallHandler(new FlutterIapPlugin(registrar.activity()));
    }


    private FlutterIapPlugin(final Activity activity) {
        this.activity = activity;
        this.storedPurchases = new HashMap<String, Purchase>();
        activity.getApplication().registerActivityLifecycleCallbacks(new Application.ActivityLifecycleCallbacks() {
            @Override
            public void onActivityCreated(Activity activity, Bundle savedInstanceState) {

            }

            @Override
            public void onActivityStarted(Activity activity) {

            }

            @Override
            public void onActivityResumed(Activity activity) {

            }

            @Override
            public void onActivityPaused(Activity activity) {

            }

            @Override
            public void onActivityStopped(Activity activity) {

            }

            @Override
            public void onActivitySaveInstanceState(Activity activity, Bundle outState) {

            }

            @Override
            public void onActivityDestroyed(Activity activity) {
                if(billingManager != null) {
                    billingManager.destroy();
                    billingManager = null;
                }
            }
        });
    }

    @Override
    public void onMethodCall(final MethodCall call, final Result result) {
        if (call.method.equals("fetch")) {
            billingManager = new BillingManager(activity, new BillingManager.BillingUpdatesListener() {
                @Override
                public void onBillingClientSetupFinished() {
                    billingManager.querySkuDetailsAsync(SkuType.SUBS, (List<String>) call.arguments,  new SkuDetailsResponseListener() {
                        @Override
                        public void onSkuDetailsResponse(int responseCode,
                                                         List<SkuDetails> skuDetailsList) {
                            if(responseCode == BillingResponse.OK) {

                                HashMap<String, HashMap<String, String>> out = new HashMap<String, HashMap<String, String>>();
                                for (Iterator<SkuDetails> i = skuDetailsList.iterator(); i.hasNext(); ) {
                                    SkuDetails d = i.next();

                                    HashMap<String, String> v = new HashMap<String, String>();
                                    v.put("description", d.getDescription());
                                    v.put("title", d.getTitle());
                                    v.put("price", String.valueOf((double) d.getPriceAmountMicros() / 1000000));
                                    v.put("localPrice", d.getPrice());
                                    v.put("subscriptionUnit", d.getSubscriptionPeriod());
                                    v.put("subscriptionQuantity", "1");

                                    out.put(d.getSku(), v);

                                }

                                result.success(out);
                            }else{
                                Log.e("getSKU", "get SKU details failed " + responseCode);
                            }
                        }
                    });
                }

                @Override
                public void onConsumeFinished(String token, @BillingClient.BillingResponse int result) {
                    Log.e("token", token);
                }

                @Override
                public void onPurchasesUpdated(List<Purchase> purchases) {
                    Log.e("purchases", purchases.toString());
                }

                @Override
                public void onPurchasesError(String err) {
                    Log.e("error: ", err);
                }
            });



        }
        if (call.method.equals("getTransaction")) {
            final String transactionId = (String) call.arguments;
            if( storedPurchases.containsKey(transactionId) ) {
                result.success( purchase2map(storedPurchases.get(transactionId)) );
            }else{
                result.success(null);
            }

        }
        if (call.method.equals("buy")) {
            final String sku = (String) call.arguments;
            billingManager = new BillingManager(activity, new BillingManager.BillingUpdatesListener() {
                @Override
                public void onBillingClientSetupFinished() {
                    billingManager.initiatePurchaseFlow(sku, BillingClient.SkuType.INAPP);
                }

                @Override
                public void onConsumeFinished(String token, @BillingClient.BillingResponse int result) {
                    Log.e("token", token);
                }

                @Override
                public void onPurchasesUpdated(List<Purchase> purchases) {
                    Log.e("purchases", purchases.toString());
                    long best = 0;
                    Purchase bestPurchase = null;
                    for (Purchase purchase : purchases) {
                        Log.e("Purchase id ", purchase.getOrderId()+" "+sku+" "+purchase.getSku());
                        if( purchase.getSku().equals(sku) && (best == 0 || purchase.getPurchaseTime() > best) ) {
                            best = purchase.getPurchaseTime();
                            bestPurchase = purchase;
                        }
                    }
                    if (bestPurchase != null) {
                        Log.e("Consuming", bestPurchase.getSku());
                        billingManager.consumeAsync(bestPurchase.getPurchaseToken());
                        storedPurchases.put(bestPurchase.getOrderId(), bestPurchase);
                        result.success(bestPurchase.getOrderId());
                    }
                }

                @Override
                public void onPurchasesError(String err) {
                    result.success("error: "+err);
                }
            });
        }

        if (call.method.equals("getTransactions")) {
            billingManager = new BillingManager(activity, new BillingManager.BillingUpdatesListener() {
                @Override
                public void onBillingClientSetupFinished() {
                }

                @Override
                public void onConsumeFinished(String token, @BillingClient.BillingResponse int result) {
                    Log.e("token", token);
                }

                @Override
                public void onPurchasesUpdated(List<Purchase> purchases) {
                    Log.e("purchases", purchases.toString());
                    HashMap<String, HashMap<String,String>> out = new HashMap<String, HashMap<String,String>>();
                    for(Iterator<Purchase> i = purchases.iterator(); i.hasNext();) {
                        Purchase p = i.next();
                        final String id = p.getPurchaseToken();
                        HashMap<String,String> v = new HashMap<String,String>();
                        v.put("productId", p.getSku());
                        out.put(id, v);
                    }
                    result.success(out);
                }

                @Override
                public void onPurchasesError(String err) {
                    result.success("error: "+err);
                }
            });
        }


    }

    private Map<String,String> purchase2map(Purchase p) {
        final Map<String, String> v = new HashMap<String, String>();
        v.put("productId", p.getSku());
        v.put("transactionId", p.getPurchaseToken());
        v.put("signature", p.getSignature());
        final Date dt = new Date(p.getPurchaseTime());
        final SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");
        v.put("date", sdf.format( dt ));
        v.put("state", "Purchased");

        return v;
    }

}
