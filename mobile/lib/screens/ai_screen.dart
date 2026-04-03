import 'package:flutter/material.dart';

class AIScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF1e1e2f),

      appBar: AppBar(
        title: Text("AI Assistant",
        style: TextStyle(color: Colors.white70)),
        foregroundColor: Colors.white,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),

      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Text(
                "Chat with AI here 🤖",
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),

          Container(
            padding: EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    style: TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "Ask something...",
                      hintStyle: TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Color(0xFF12121f),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Icon(Icons.send, color: Colors.white),
              ],
            ),
          )
        ],
      ),
    );
  }
}