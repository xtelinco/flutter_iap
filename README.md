# IMPORTANT NOTICE

You are free to use this code, but it is totally unsupported. Various changes were needed for another project and a lot of the changes are custom for that project. It isn't backward compatible with the main flutter_iap branch.

# flutter_iap

Add _In-App Payments_ to your Flutter app with this plugin.

## Getting Started

For help getting started with Flutter, view our online
[documentation](http://flutter.io/).

For help on editing plugin code, view the [documentation](https://flutter.io/platform-plugins/#edit-code).

## Install

Add ```flutter_iap``` as a dependency in pubspec.yaml

For help on adding as a dependency, view the [documentation](https://flutter.io/using-packages/).

## Example
```dart
import 'package:flutter/material.dart';
import 'package:flutter_iap/flutter_iap.dart';

void main() {
  runApp(new MyApp());
}

class MyApp extends StatefulWidget {
  @override _MyAppState createState() => new _MyAppState();
}

class _MyAppState extends State<MyApp> {

  List<String> _productIds = [];

  @override initState() {
    super.initState();
    init();
  }

  init() async {
    List<String> productIds = await FlutterIap.fetchProducts(["com.example.testiap"]);

    if (!mounted)
      return;

    setState(() {
      _productIds = productIds;
    });
  }

  @override Widget build(BuildContext context) {
    return new MaterialApp(
      home: new Scaffold(
        appBar: new AppBar(
          title: new Text('IAP example app'),
        ),
        body: new Center(
          child: new Text('Fetched: $_productIds\n'),
        ),
        floatingActionButton: new FloatingActionButton(
          child: new Icon(Icons.monetization_on),
          onPressed: () {
            FlutterIap.buy(_productIds.first);
          },
        ),
      ),
    );
  }
}
```
