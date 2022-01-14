import 'package:apollo_11/pages/home_page.dart';
import 'package:flutter/material.dart';

void main() {
  // ignore: prefer_const_constructors
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    int days = 11;
    String name = "darshan";


    return MaterialApp(
        home: HomePage(),
        );
  }
}
