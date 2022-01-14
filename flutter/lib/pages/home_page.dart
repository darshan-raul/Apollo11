import 'package:flutter/material.dart';

import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({ Key? key }) : super(key: key);

  final days = 11;
  final name = "darshan";

  @override
  Widget build(BuildContext context) {
    
    return Scaffold(
      appBar: AppBar(
        title: Text("Apollo 11"),
      ),
      body: Center(
      child: Container(
          // ignore: prefer_const_constructors
          child: Text("Welcome to Apollo $days by $name"))),
          drawer: Drawer(),
          );
      
  }
}