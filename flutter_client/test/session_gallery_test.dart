import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_collie_flutter/api.dart';
import 'package:g_collie_flutter/resources.dart';
import 'package:g_collie_flutter/session_video.dart';
class GalleryApi extends CollieApi{
 final List<String> paths=[];
 GalleryApi():super(Uri.parse('http://preview.invalid'));
 @override Future<dynamic> call(String path,[Json? body])async{paths.add(path);return {'resources':[{'id':'a','ref':'/one.png','image':true,'name':'one'},{'id':'b','ref':'/two.png','image':true,'name':'two'},{'id':'v','ref':'/clip.mp4','image':false,'name':'clip'}]};}
}
class GalleryResources extends SessionResources{
 final reads=<String,int>{};
 GalleryResources(super.api,super.session);
 @override Future<Uint8List> image(String ref)async { reads[ref]=(reads[ref]??0)+1;return base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a2ioAAAAASUVORK5CYII='); }
}
void main(){testWidgets('media swipe stays in the selected session and includes video',(tester)async{
 final api=GalleryApi();final resources=GalleryResources(api,'hermes:only-this');
 await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:()=>resources.gallery(context,'/one.png'),child:const Text('打开'))))));
 await tester.tap(find.text('打开'));await tester.pumpAndSettle();expect(find.text('1 / 3'),findsOneWidget);expect(api.paths,['/local/hermes%3Aonly-this/resources']);
 await tester.drag(find.byKey(const ValueKey('session-gallery')),const Offset(-650,0));await tester.pumpAndSettle();expect(find.text('2 / 3'),findsOneWidget);
 await tester.tap(find.byTooltip('下一个媒体'));await tester.pumpAndSettle();expect(find.text('3 / 3'),findsOneWidget);expect(find.byType(SessionVideo),findsOneWidget);
 await tester.drag(find.byKey(const ValueKey('session-gallery')),const Offset(650,0));await tester.pumpAndSettle();expect(find.byType(SessionVideo),findsNothing);expect(find.text('2 / 3'),findsOneWidget);
 expect(resources.reads['/two.png'],1);expect(resources.reads['/one.png'],1);
 await tester.pumpWidget(const SizedBox());api.close();
 });}
