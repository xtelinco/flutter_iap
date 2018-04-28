import 'dart:async';

import 'package:flutter/services.dart';

class FlutterIap {
  static const MethodChannel _channel = const MethodChannel('flutter_iap');

  static Future<Map<String,Map<String,String>>> fetchProducts(List<String> ids) => _channel.invokeMethod("fetch", ids).then((result) {
    print(result);
    if(result == null) { return null; }
    final out = Map<String, Map<String,String>>();
    result.forEach((k,v) {
      out[k] = new Map<String, String>();
      v.forEach((k2,v2) {
        out[k][k2] = v2;
      });
    });
    return out;
  });



  static Future<Map<String,String>> getTransaction(String id) => _channel.invokeMethod("getTransaction", id).then((result) {
    if(result == null) { return null; }
    final out = Map<String,String>();
    for(var k in result.keys) {
      out[k] = result[k];
    }
    return out;
  });

  static Future<String> buy(String id) => _channel.invokeMethod("buy", id).then((result) {
    return result as String;
  });

  static Future<Map<String,Map<String,String>>> getTransactions() => _channel.invokeMethod("getTransactions").then((result) {
    if(result == null) { return null; }
    final out = Map<String, Map<String,String>>();
    for(var k in result.keys) {
      out[k] = new Map<String,String>();
      for(var k2 in result[k].keys) {
        out[k][k2] = result[k][k2];
      }
    }
    return out;
  });
  static Future<String> subscriptionValid(String sharedSecret) => _channel.invokeMethod("subscriptionValid", sharedSecret).then((result) { return result as String; });
}
