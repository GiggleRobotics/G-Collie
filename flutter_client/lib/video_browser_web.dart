import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

Widget browserVideo(Uri url) => HtmlElementView.fromTagName(
  tagName: 'video',
  onElementCreated: (element) {
    pauseBrowserVideos();
    final video = element as web.HTMLVideoElement;
    video.src = url.path.endsWith('.mp4')
        ? url.toString()
        : url.resolve('./content').toString();
    video.controls = true;
    video.autoplay = true;
    video.setAttribute('playsinline', '');
    video.style.width = '100%';
    video.style.height = '100%';
    video.style.objectFit = 'contain';
    video.style.backgroundColor = '#000';
  },
);
void pauseBrowserVideos() {
  final videos = web.document.querySelectorAll('video');
  for (var i = 0; i < videos.length; i++) {
    final video = videos.item(i) as web.HTMLVideoElement;
    video.autoplay = false;
    video.pause();
  }
}
