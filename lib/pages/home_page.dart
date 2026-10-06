import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const new({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Personal OS')),
      // body: Center(child: const Text('Hello World!')),
      body: SafeArea(
        // child: Row(
        //   mainAxisAlignment: MainAxisAlignment.start,
        //   crossAxisAlignment: CrossAxisAlignment.stretch,
        //   children: [
        //     Container(
        //       color: Colors.amber,
        //       width: 100,
        //       height: 100,
        //       child: Text("A", style: TextStyle(color: Colors.black)),
        //     ),
        //     Container(
        //       color: Colors.blue,
        //       width: 100,
        //       height: 100,
        //       child: Text("B", style: TextStyle(color: Colors.black)),
        //     ),
        //     Container(
        //       color: Colors.brown,
        //       width: 100,
        //       height: 100,
        //       child: Text("C", style: TextStyle(color: Colors.black)),
        //     ),
        //   ],
        // ),
        child: GridView.count(
          crossAxisCount: 2, // 2 columns
          children: [
            Container(color: Colors.red, height: 100),
            Container(color: Colors.blue, height: 100),
          ],
        ),
      ),
    );
  }
}
