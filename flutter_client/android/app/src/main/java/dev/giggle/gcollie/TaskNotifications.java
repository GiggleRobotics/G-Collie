package dev.giggle.gcollie;

import android.app.*;
import android.content.*;
import android.os.*;
import org.json.*;
import java.net.*;
import java.io.*;
import java.util.concurrent.*;

/** User-enabled foreground synchronization; no public push relay or account secrets. */
public class TaskNotifications extends Service {
 private final ScheduledExecutorService worker=Executors.newSingleThreadScheduledExecutor();
 private volatile String origin="",cookie="",remote="";
 public static volatile boolean running=false;
 private volatile boolean closed=false;
 private volatile long cursor=-1;
 private int failures=0;
 private boolean offline=false;
 private NotificationManager manager;
 private static final String CHANNEL="task-events",CONNECTION="connection";
 private static final int ONGOING=4100,NETWORK=4101;
 @Override public void onCreate(){super.onCreate();manager=(NotificationManager)getSystemService(NOTIFICATION_SERVICE);manager.createNotificationChannel(new NotificationChannel(CHANNEL,"任务状态提醒",NotificationManager.IMPORTANCE_DEFAULT));manager.createNotificationChannel(new NotificationChannel(CONNECTION,"后台连接状态",NotificationManager.IMPORTANCE_LOW));worker.scheduleWithFixedDelay(()->poll(),1,5,TimeUnit.SECONDS);}
 private PendingIntent open(String id){Intent intent=new Intent(this,dev.giggle.g_collie_flutter.MainActivity.class);intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TOP);intent.putExtra("server",remote+(id.isEmpty()?"/":"/?session="+UriEncode(id)));return PendingIntent.getActivity(this,id.isEmpty()?0:id.hashCode(),intent,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);}
 private String UriEncode(String value){return android.net.Uri.encode(value);}
 private Notification notification(String body,String id,boolean ongoing){Notification.Builder b=new Notification.Builder(this,ongoing?CONNECTION:CHANNEL).setSmallIcon(android.R.drawable.ic_dialog_info).setContentTitle("G-Collie").setContentText(body).setContentIntent(open(id)).setVisibility(Notification.VISIBILITY_PRIVATE).setOnlyAlertOnce(ongoing).setOngoing(ongoing).setAutoCancel(!ongoing);if(ongoing){Intent stop=new Intent(this,TaskNotifications.class).setAction("stop");b.addAction(new Notification.Action.Builder(null,"停止提醒",PendingIntent.getService(this,0,stop,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE)).build());}return b.build();}
 @Override public int onStartCommand(Intent intent,int flags,int startId){if(intent==null||"stop".equals(intent.getAction())){getSharedPreferences("connection",MODE_PRIVATE).edit().putBoolean("notifications",false).apply();stopSelf();return START_NOT_STICKY;}String next=intent.getStringExtra("origin"),credential=intent.getStringExtra("cookie"),target=intent.getStringExtra("remote");if(next==null||credential==null||target==null){stopSelf();return START_NOT_STICKY;}try{URI u=new URI(next);if(u.getHost()==null||!("http".equals(u.getScheme())||"https".equals(u.getScheme()))||!credential.contains("gcollie_device=")){stopSelf();return START_NOT_STICKY;}}catch(Exception e){stopSelf();return START_NOT_STICKY;}boolean changed=!target.equals(remote);origin=next;cookie=credential;remote=target;if(changed){cursor=-1;failures=0;}getSharedPreferences("connection",MODE_PRIVATE).edit().putBoolean("notificationsRunning",true).apply();running=true;startForeground(ONGOING,notification("正在同步任务状态，点击返回工作台","",true));return START_NOT_STICKY;}
 private void alert(String body,String id,int number){if(closed)return;try{manager.notify(number,notification(body,id,false));}catch(SecurityException ignored){}}
 private synchronized void poll(){if(origin.isEmpty())return;HttpURLConnection connection=null;try{String request=origin+"/api/notifications/feed"+(cursor<0?"":"?after="+cursor);connection=(HttpURLConnection)new URL(request).openConnection();connection.setConnectTimeout(8000);connection.setReadTimeout(8000);connection.setInstanceFollowRedirects(false);connection.setRequestProperty("Cookie",cookie);int code=connection.getResponseCode();if(code==401||code==403){getSharedPreferences("connection",MODE_PRIVATE).edit().putBoolean("notifications",false).apply();alert("设备授权已失效，请打开 App 重新配对","",NETWORK);stopSelf();return;}if(code!=200)throw new IOException("unavailable");ByteArrayOutputStream data=new ByteArrayOutputStream();try(InputStream input=connection.getInputStream()){byte[] buffer=new byte[4096];int length;while((length=input.read(buffer))!=-1){data.write(buffer,0,length);if(data.size()>131072)throw new IOException("too large");}}if(closed)return;JSONObject feed=new JSONObject(data.toString("UTF-8"));JSONArray events=feed.optJSONArray("events");if(events!=null&&cursor>=0)for(int i=0;i<events.length();i++){JSONObject event=events.getJSONObject(i);String id=event.optString("sessionId");if(!id.matches("^(codex|hermes):[a-zA-Z0-9_-]+$"))continue;alert(event.optString("body","任务状态已更新"),id,5000+Math.floorMod(id.hashCode(),100000));}cursor=feed.getLong("cursor");failures=0;offline=false;manager.cancel(NETWORK);manager.notify(ONGOING,notification("已连接电脑 · 关注 "+feed.optInt("watched")+" 个会话","",true));}catch(Exception e){if(closed)return;if(++failures>=3&&!offline){offline=true;alert("电脑连接中断，任务状态未知；正在重试","",NETWORK);manager.notify(ONGOING,notification("连接中断，正在重试","",true));}}finally{if(connection!=null)connection.disconnect();}}
 @Override public void onTimeout(int startId,int type){getSharedPreferences("connection",MODE_PRIVATE).edit().putBoolean("notifications",false).apply();alert("后台同步已达系统时限，请打开 App 后重新开启提醒","",NETWORK);stopSelf();}
 @Override public void onDestroy(){closed=true;running=false;worker.shutdownNow();getSharedPreferences("connection",MODE_PRIVATE).edit().putBoolean("notificationsRunning",false).apply();stopForeground(STOP_FOREGROUND_REMOVE);super.onDestroy();}
 @Override public IBinder onBind(Intent intent){return null;}
}
