import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meet_videosdk/presentation/common/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: VideoSdkApp()));
}

class VideoSdkApp extends StatelessWidget {
  const VideoSdkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VideoSDK Call',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const Scaffold(
        body: Center(child: Text('VideoSDK Call')),
      ),
    );
  }
}
