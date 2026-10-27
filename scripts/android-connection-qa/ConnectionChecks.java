package dev.giggle.qa;
import android.app.*;
import android.content.*;
import android.os.*;
import android.service.notification.StatusBarNotification;
import java.net.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicBoolean;

public class ConnectionChecks extends Instrumentation {
 private final AtomicBoolean available=new AtomicBoolean(true);
 private ServerSocket server;
 private volatile boolean closed=false;
 private Context target;
 private NotificationManager manager;
 private String notification(int id){for(StatusBarNotification n:manager.getActiveNotifications())if(n.getId()==id)return n.getNotification().extras.getCharSequence(Notification.EXTRA_TEXT,"").toString();return "";}
 private void require(boolean condition,String message){if(!condition)throw new AssertionError(message);}
 private void waitFor(int id,String text,long timeout)throws Exception{long end=System.currentTimeMillis()+timeout;while(System.currentTimeMillis()<end){if(notification(id).contains(text))return;Thread.sleep(250);}throw new AssertionError("Expected notification "+id+" containing "+text+", actual="+notification(id));}
 private void serve(Socket socket){try(socket){socket.setSoTimeout(4000);BufferedReader in=new BufferedReader(new InputStreamReader(socket.getInputStream()));String line;while((line=in.readLine())!=null&&!line.isEmpty()){}boolean ok=available.get();byte[] body=(ok?"{\"cursor\":1,\"watched\":0,\"events\":[]}":"{\"error\":\"qa-offline\"}").getBytes(StandardCharsets.UTF_8);OutputStream out=socket.getOutputStream();out.write(((ok?"HTTP/1.1 200 OK":"HTTP/1.1 503 Unavailable")+"\r\nContent-Type: application/json\r\nContent-Length: "+body.length+"\r\nConnection: close\r\n\r\n").getBytes(StandardCharsets.UTF_8));out.write(body);out.flush();}catch(Exception ignored){}}
 @Override public void onCreate(Bundle args){super.onCreate(args);start();}
 @Override public void onStart(){Bundle result=new Bundle();Intent service=null;boolean original=false;try{
  target=getTargetContext();manager=(NotificationManager)target.getSystemService(Context.NOTIFICATION_SERVICE);original=target.getSharedPreferences("connection",0).getBoolean("notifications",false);

  server=new ServerSocket(0,50,InetAddress.getByName("127.0.0.1"));Thread listener=new Thread(()->{while(!closed)try{Socket socket=server.accept();new Thread(()->serve(socket)).start();}catch(Exception ignored){}});listener.setDaemon(true);listener.start();
  service=new Intent().setClassName(target,"dev.giggle.gcollie.TaskNotifications").putExtra("origin","http://127.0.0.1:"+server.getLocalPort()).putExtra("cookie","gcollie_device=qa-fixture-not-a-real-credential").putExtra("remote","http://qa.invalid:4310");
  target.startForegroundService(service);waitFor(4100,"已连接电脑",15000);require(!notification(4101).contains("已恢复"),"initial connection must not alert recovery");
  available.set(false);waitFor(4101,"连接中断",25000);require(notification(4100).contains("连接中断"),"ongoing status should show interruption");
  available.set(true);waitFor(4101,"连接已恢复",15000);waitFor(4100,"已连接电脑",5000);
  long posted=0;for(StatusBarNotification n:manager.getActiveNotifications())if(n.getId()==4101)posted=n.getPostTime();Thread.sleep(6500);long after=0;for(StatusBarNotification n:manager.getActiveNotifications())if(n.getId()==4101)after=n.getPostTime();require(posted==after,"healthy polls must not repeat recovery alerts");
  result.putString("stream","PASS native notification initial connection, 3-failure interruption, recovery alert, steady-state no duplicate\n");
 }catch(Throwable e){result.putString("stream","FAIL "+e.toString()+"\n");result.putString("failure",e.toString());}finally{
  closed=true;try{if(server!=null)server.close();}catch(Exception ignored){}
  if(target!=null){if(service!=null)target.stopService(service);target.getSharedPreferences("connection",0).edit().putBoolean("notifications",original).commit();if(manager!=null)manager.cancel(4101);}
  finish(result.containsKey("failure")?1:Activity.RESULT_OK,result);
 }}
}
