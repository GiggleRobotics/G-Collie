package dev.giggle.gcollie;

import android.app.*;
import android.os.*;
import android.content.*;
import android.graphics.Color;
import android.net.Uri;
import android.view.*;
import android.webkit.*;
import android.widget.*;
import org.json.JSONObject;
import java.util.concurrent.Executors;
import java.util.concurrent.ExecutorService;

public class MainActivity extends Activity {
 private WebView web;
 private ValueCallback<Uri[]> fileCallback;
 private FrameLayout frame;
 private String origin="", address="", activeRemote="";
 private android.content.SharedPreferences prefs;
 private final ExecutorService worker=Executors.newSingleThreadExecutor();
 private final Handler ui=new Handler(Looper.getMainLooper());
 private AlertDialog networkDialog;
 private boolean loginRequested=false;
 private String pendingConnection="";
 private int generation=0;
 private int dp(int v){return (int)(getResources().getDisplayMetrics().density*v);}
 @Override public void onCreate(Bundle state){
  super.onCreate(state);prefs=getSharedPreferences("connection",MODE_PRIVATE);
  getWindow().setStatusBarColor(Color.WHITE);getWindow().setNavigationBarColor(Color.WHITE);
  getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR|View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
  frame=new FrameLayout(this);frame.setBackgroundColor(Color.WHITE);setContentView(frame);
  frame.setOnApplyWindowInsetsListener((v,insets)->{v.setPadding(insets.getSystemWindowInsetLeft(),insets.getSystemWindowInsetTop(),insets.getSystemWindowInsetRight(),insets.getSystemWindowInsetBottom());return insets.consumeSystemWindowInsets();});
  address=prefs.getString("address","");String extra=incoming(getIntent());if(extra!=null)address=extra;
  if(address.isEmpty())settings();else connect(address);
  ui.postDelayed(new Runnable(){public void run(){if(isDestroyed())return;saveCookies();CookieManager.getInstance().flush();ui.postDelayed(this,5000);}},5000);
 }
 private String incoming(Intent intent){
  Uri uri=intent.getData();
  if(uri!=null&&"gcollie".equals(uri.getScheme())&&"connect".equals(uri.getHost()))return uri.getQueryParameter("url");
  return intent.getStringExtra("server");
 }
 @Override protected void onNewIntent(Intent intent){super.onNewIntent(intent);setIntent(intent);String value=incoming(intent);if(value!=null){if(networkDialog!=null)networkDialog.dismiss();connect(value);}}
 private String validate(String value){
  String normalized=value.trim();
  if(!normalized.contains("://"))normalized="http://"+normalized;
  Uri u=Uri.parse(normalized);
  if(!("https".equals(u.getScheme())||"http".equals(u.getScheme()))||u.getHost()==null||u.getUserInfo()!=null)throw new IllegalArgumentException("请输入完整的 http:// 或 https:// 电脑地址");
  if(u.getPort()==-1&&("http".equals(u.getScheme()))&&(u.getHost().startsWith("100.")||u.getHost().endsWith(".ts.net")))return "http://"+u.getEncodedAuthority()+":4310";
  return u.getScheme()+"://"+u.getEncodedAuthority();
 }
 private boolean embeddedAddress(String raw){String host=Uri.parse(raw).getHost();if(host!=null)host=host.toLowerCase(java.util.Locale.ROOT).replace("[","").replace("]","");return host!=null&&(host.endsWith(".ts.net")||host.startsWith("100.")||host.startsWith("fd7a:115c:a1e0:"));}
 private void settings(){
  LinearLayout box=new LinearLayout(this);box.setOrientation(1);box.setPadding(dp(24),dp(12),dp(24),0);
  TextView note=new TextView(this);note.setText("内置私有网络：无需另装 Tailscale。先在本应用授权入网，再输入电脑 G-Collie 显示的私有网络地址或完整配对链接。\n\n例如 http://100.x.x.x:4310");box.addView(note);
  EditText field=new EditText(this);field.setSingleLine(true);field.setInputType(17);field.setHint("电脑地址 / 配对链接");field.setText(address);box.addView(field);
  AlertDialog dialog=new AlertDialog.Builder(this).setTitle("连接电脑").setView(box).setPositiveButton("连接",null).setNeutralButton("内置网络",(d,w)->networkPanel()).setNegativeButton("取消",(d,w)->{if(web==null)finish();}).create();
  dialog.setOnShowListener(d->dialog.getButton(-1).setOnClickListener(v->{try{String value=field.getText().toString().trim();validate(value);dialog.dismiss();connect(value);}catch(Exception e){field.setError(e.getMessage());}}));dialog.show();
 }
 private JSONObject checked(String raw)throws Exception{JSONObject value=new JSONObject(raw);if(value.has("error"))throw new Exception(value.getString("error"));return value;}
 private void startNetwork()throws Exception{
  android.net.ConnectivityManager cm=(android.net.ConnectivityManager)getSystemService(CONNECTIVITY_SERVICE);
  android.net.LinkProperties link=cm.getLinkProperties(cm.getActiveNetwork());
  JSONObject description=new JSONObject();org.json.JSONArray addresses=new org.json.JSONArray();
  if(link!=null){description.put("name",link.getInterfaceName());description.put("mtu",link.getMtu());for(android.net.LinkAddress a:link.getLinkAddresses())addresses.put(a.getAddress().getHostAddress().split("%")[0]+"/"+a.getPrefixLength());for(android.net.RouteInfo route:link.getRoutes())if(route.isDefaultRoute()&&route.getGateway()!=null){description.put("gateway",route.getGateway().getHostAddress());break;}}
  description.put("addresses",addresses);checked(NativeNetwork.configureNetwork(description.toString()));
  checked(NativeNetwork.start(new java.io.File(getFilesDir(),"tailnet").getAbsolutePath()));}
 private void error(String message){if(!isFinishing()&&!isDestroyed())new AlertDialog.Builder(this).setTitle("连接提示").setMessage(message).setPositiveButton("内置网络",(d,w)->networkPanel()).setNegativeButton("关闭",null).show();}
 private void networkPanel(){
  if(isFinishing()||isDestroyed()||(networkDialog!=null&&networkDialog.isShowing()))return;
  LinearLayout box=new LinearLayout(this);box.setOrientation(1);box.setPadding(dp(24),dp(12),dp(24),0);
  TextView status=new TextView(this);status.setText("正在启动内置私有网络…");box.addView(status);
  LinearLayout computers=new LinearLayout(this);computers.setOrientation(1);box.addView(computers);
  TextView note=new TextView(this);note.setText("本应用会作为独立设备加入你的 Tailscale 网络。首次需在系统浏览器登录授权；不会接管其他应用的流量。电脑和手机须加入同一有访问权限的网络。");box.addView(note);
  Button login=new Button(this);login.setText("登录 / 授权入网");box.addView(login);
  login.setOnClickListener(v->{login.setEnabled(false);loginRequested=true;worker.execute(()->{try{startNetwork();JSONObject state=checked(NativeNetwork.status());if(state.optString("authURL").isEmpty())checked(NativeNetwork.login());}catch(Throwable e){loginRequested=false;ui.post(()->error(e.getMessage()));}ui.post(()->login.setEnabled(true));});});
  ScrollView networkScroll=new ScrollView(this);networkScroll.addView(box);
  networkDialog=new AlertDialog.Builder(this).setTitle("内置远程连接").setView(networkScroll).setPositiveButton("电脑地址",(d,w)->settings()).setNegativeButton("关闭",null).setNeutralButton("退出账号",(d,w)->new AlertDialog.Builder(this).setMessage("退出内置网络并清除本应用保存的设备登录？远程任务仍在电脑运行。").setPositiveButton("退出",(d2,w2)->{generation++;stopService(new Intent(this,TaskNotifications.class));worker.execute(()->{try{startNetwork();checked(NativeNetwork.logout());ui.post(()->{prefs.edit().clear().apply();CookieManager.getInstance().removeAllCookies(null);activeRemote="";address="";if(web!=null)web.loadUrl("about:blank");settings();});}catch(Throwable e){ui.post(()->error(e.getMessage()));}});}).setNegativeButton("取消",null).show()).create();
  networkDialog.show();final AlertDialog owner=networkDialog;
  Runnable poll=new Runnable(){public void run(){if(networkDialog!=owner||!owner.isShowing()||isDestroyed())return;worker.execute(()->{try{startNetwork();JSONObject state=checked(NativeNetwork.status());String value=state.optString("state","Starting"),link=state.optString("authURL","");ui.post(()->{if(networkDialog!=owner||!owner.isShowing())return;computers.removeAllViews();org.json.JSONArray peers=state.optJSONArray("computers");
     if(value.equals("Running")&&peers!=null&&peers.length()>0){TextView heading=new TextView(MainActivity.this);heading.setText("发现你的电脑（需保持电脑服务运行）");computers.addView(heading);for(int i=0;i<peers.length();i++){JSONObject peer=peers.optJSONObject(i);if(peer==null)continue;final String remote=peer.optString("address");Button choice=new Button(MainActivity.this);choice.setText(peer.optString("name")+"\n"+remote);choice.setOnClickListener(v->{pendingConnection="";owner.dismiss();connect(remote);});computers.addView(choice);}}
     String text=value.equals("Running")?"已加入私有网络，可以连接电脑":value.equals("NeedsMachineAuth")?"等待网络管理员批准此设备":value.equals("NeedsLogin")?"请点击登录，授权本应用入网":"正在连接："+value;status.setText(text);login.setEnabled(value.equals("NeedsLogin"));if(value.equals("Running")&&!pendingConnection.isEmpty()){String next=pendingConnection;pendingConnection="";owner.dismiss();connect(next);return;}if(loginRequested&&!link.isEmpty()){Uri u=Uri.parse(link);if("https".equals(u.getScheme())&&"login.tailscale.com".equals(u.getHost())){loginRequested=false;try{startActivity(new Intent(Intent.ACTION_VIEW,u));}catch(ActivityNotFoundException absent){new AlertDialog.Builder(MainActivity.this).setTitle("在浏览器完成授权").setMessage(link).setPositiveButton("复制登录入口",(d,w)->{((android.content.ClipboardManager)getSystemService(CLIPBOARD_SERVICE)).setPrimaryClip(ClipData.newPlainText("Tailscale 登录入口",link));}).setNegativeButton("关闭",null).show();}}}});}catch(Throwable e){ui.post(()->status.setText("网络启动失败："+e.getMessage()));}ui.postDelayed(this,2000);});}};poll.run();
 }
 private void saveCookies(){if(!activeRemote.isEmpty()&&!origin.isEmpty()){String cookies=CookieManager.getInstance().getCookie(origin);prefs.edit().putString("cookies:"+activeRemote,cookies==null?"":cookies).apply();}}
 private void connect(String value){
  try{validate(value);}catch(Exception e){error(e.getMessage());return;}
  pendingConnection="";stopService(new Intent(this,TaskNotifications.class));
  Uri supplied=Uri.parse(value.trim().contains("://")?value.trim():"http://"+value.trim());
  value=validate(value)+(supplied.getEncodedPath()==null?"/":supplied.getEncodedPath())+(supplied.getEncodedQuery()==null?"":"?"+supplied.getEncodedQuery())+(supplied.getEncodedFragment()==null?"":"#"+supplied.getEncodedFragment());
  final String destination=value;
  final int request=++generation;saveCookies();address=validate(value);prefs.edit().putString("address",address).apply();
  if(!embeddedAddress(value)){activeRemote="";render(value,"");return;}
  Toast.makeText(this,"正在通过内置私有网络连接…",Toast.LENGTH_SHORT).show();
  worker.execute(()->{try{startNetwork();JSONObject state=checked(NativeNetwork.status());for(int attempt=0;attempt<40&&java.util.Arrays.asList("NoState","Starting","Stopped").contains(state.optString("state"));attempt++){Thread.sleep(250);state=checked(NativeNetwork.status());}if(!"Running".equals(state.optString("state"))){ui.post(()->{if(request==generation){pendingConnection=destination;networkPanel();}});return;}JSONObject result=checked(NativeNetwork.open(destination));ui.post(()->{if(request==generation)render(result.optString("url"),result.optString("token"));});}catch(Throwable e){ui.post(()->{if(request==generation)error(e.getMessage());});}});
 }
 private void render(String value,String token){
  origin=validate(value);activeRemote=address;
  if(web!=null){frame.removeAllViews();web.destroy();}
  web=new WebView(this);WebSettings s=web.getSettings();s.setJavaScriptEnabled(true);s.setDomStorageEnabled(true);s.setAllowFileAccess(false);s.setAllowContentAccess(false);s.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);s.setMediaPlaybackRequiresUserGesture(true);
  CookieManager cookies=CookieManager.getInstance();cookies.setAcceptCookie(true);cookies.setAcceptThirdPartyCookies(web,false);
  web.setWebChromeClient(new WebChromeClient(){
   @Override public boolean onShowFileChooser(WebView view,ValueCallback<Uri[]> callback,FileChooserParams params){
    android.util.Log.i("GColliePicker","Opening system file picker");if(fileCallback!=null)fileCallback.onReceiveValue(null);fileCallback=callback;
    try{Intent picker=params.createIntent();picker.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);startActivityForResult(picker,702);}catch(ActivityNotFoundException e){fileCallback.onReceiveValue(null);fileCallback=null;Toast.makeText(MainActivity.this,"手机没有可用的文件选择器",Toast.LENGTH_LONG).show();}return true;
   }
  });web.setWebViewClient(new WebViewClient(){
   @Override public boolean shouldOverrideUrlLoading(WebView view,WebResourceRequest request){Uri u=request.getUrl();String dest=u.getScheme()+"://"+u.getEncodedAuthority();if(origin.equals(dest))return false;if(!activeRemote.isEmpty()&&activeRemote.equals(dest)){web.loadUrl(origin+u.getEncodedPath()+(u.getEncodedQuery()==null?"":"?"+u.getEncodedQuery())+(u.getEncodedFragment()==null?"":"#"+u.getEncodedFragment()));return true;}if("https".equals(u.getScheme())||"http".equals(u.getScheme()))new AlertDialog.Builder(MainActivity.this).setMessage("在浏览器打开此链接？内置私有网络只供本应用使用。").setPositiveButton("打开",(d,w)->{try{startActivity(new Intent(Intent.ACTION_VIEW,u));}catch(Exception e){}}).setNegativeButton("取消",null).show();return true;}
   @Override public void onPageFinished(WebView view,String url){if(view!=web)return;CookieManager.getInstance().flush();saveCookies();if(prefs.getBoolean("notifications",false)&&hasWindowFocus())startReminder();}
   @Override public void onReceivedError(WebView view,WebResourceRequest req,WebResourceError error){if(req.isForMainFrame())failure();}
   @Override public void onReceivedHttpError(WebView view,WebResourceRequest req,WebResourceResponse response){if(req.isForMainFrame()&&response.getStatusCode()>=500)failure();}
  });
  FrameLayout.LayoutParams browserLayout=new FrameLayout.LayoutParams(-1,-1);browserLayout.topMargin=dp(40);frame.addView(web,browserLayout);
  TextView brand=new TextView(this);brand.setText(token.isEmpty()?"G-Collie":"G-Collie · 内置私有连接");brand.setTextSize(14);brand.setTextColor(Color.DKGRAY);brand.setPadding(dp(16),dp(10),0,0);frame.addView(brand,new FrameLayout.LayoutParams(-1,dp(40),Gravity.TOP));
  Button menu=new Button(this);menu.setText("⋮");menu.setTextSize(22);menu.setContentDescription("电脑连接设置");menu.setBackgroundColor(Color.TRANSPARENT);FrameLayout.LayoutParams lp=new FrameLayout.LayoutParams(dp(40),dp(44),Gravity.RIGHT|Gravity.TOP);frame.addView(menu,lp);menu.setOnClickListener(v->{PopupMenu popup=new PopupMenu(this,menu);popup.getMenu().add("任务提醒").setOnMenuItemClickListener(i->{reminderPanel();return true;});popup.getMenu().add("内置网络").setOnMenuItemClickListener(i->{networkPanel();return true;});popup.getMenu().add("重新连接").setOnMenuItemClickListener(i->{connect(address);return true;});popup.getMenu().add("切换电脑").setOnMenuItemClickListener(i->{settings();return true;});popup.show();});
  // Clear the previous computer's jar before restoring this computer's credential.
  final WebView targetView=web;final String jar=prefs.getString("cookies:"+activeRemote,"");final String browserOrigin=origin;
  cookies.removeAllCookies(done->{if(web!=targetView)return;{for(String entry:jar.split(";")){String pair=entry.trim();if(pair.startsWith("gcollie_device="))cookies.setCookie(browserOrigin,pair+"; Path=/; HttpOnly; SameSite=Strict");}if(!token.isEmpty())cookies.setCookie(browserOrigin,"gcollie_gateway="+token+"; Path=/; HttpOnly; SameSite=Strict");}cookies.flush();targetView.loadUrl(value);});
 }
 private void startReminder(){
  if(origin.isEmpty()||!origin.startsWith("http://127.0.0.1:")||!prefs.getBoolean("notifications",false))return;
  String jar=CookieManager.getInstance().getCookie(origin);if(jar==null||!jar.contains("gcollie_device="))return;
  Intent intent=new Intent(this,TaskNotifications.class).putExtra("origin",origin).putExtra("cookie",jar).putExtra("remote",address);
  try{startForegroundService(intent);}catch(Exception e){prefs.edit().putBoolean("notifications",false).apply();Toast.makeText(this,"系统暂不允许后台同步，请保持 App 打开后重试",Toast.LENGTH_LONG).show();}
 }
 private void reminderPanel(){
  boolean enabled=prefs.getBoolean("notifications",false)&&TaskNotifications.running;
  new AlertDialog.Builder(this).setTitle("任务提醒").setMessage((enabled?"后台同步已开启。":"后台同步未运行。")+"\n开启后可在离开 App 时收到任务结束、需要处理和断线提醒。关注最近打开的 30 个会话；不显示聊天正文。首次载入、服务重启和断线期间不会推断任务完成。\n\n需要内置网络连接和通知权限，开启后会显示常驻通知。Android 15 对此类后台同步有时长限制，达到限制后需打开 App 重新开启。省电或强制停止可能中断同步。")
   .setPositiveButton(enabled?"关闭提醒":"开启提醒",(d,w)->{if(enabled){prefs.edit().putBoolean("notifications",false).apply();stopService(new Intent(this,TaskNotifications.class));return;}if(!origin.startsWith("http://127.0.0.1:")||activeRemote.isEmpty()){error("请先通过内置网络连接并配对电脑");return;}if(Build.VERSION.SDK_INT>=33&&checkSelfPermission("android.permission.POST_NOTIFICATIONS")!=android.content.pm.PackageManager.PERMISSION_GRANTED){requestPermissions(new String[]{"android.permission.POST_NOTIFICATIONS"},701);return;}prefs.edit().putBoolean("notifications",true).apply();startReminder();}).setNegativeButton("关闭",null).show();
 }
 @Override protected void onActivityResult(int request,int result,Intent data){super.onActivityResult(request,result,data);if(request==702&&fileCallback!=null){java.util.ArrayList<Uri> chosen=new java.util.ArrayList<>();
 if(result==RESULT_OK&&data!=null){if(data.getClipData()!=null){for(int i=0;i<data.getClipData().getItemCount();i++){Uri item=data.getClipData().getItemAt(i).getUri();if(item!=null)chosen.add(item);}}else if(data.getData()!=null)chosen.add(data.getData());}
 Uri[] values=chosen.isEmpty()?WebChromeClient.FileChooserParams.parseResult(result,data):chosen.toArray(new Uri[0]);android.util.Log.i("GColliePicker","Picker result="+result+" intent="+(data!=null)+" clip="+(data!=null&&data.getClipData()!=null)+" uri="+(data!=null&&data.getData()!=null)+" files="+(values==null?0:values.length));fileCallback.onReceiveValue(values);fileCallback=null;}}
 @Override public void onRequestPermissionsResult(int request,String[] permissions,int[] grants){super.onRequestPermissionsResult(request,permissions,grants);if(request==701&&grants.length>0&&grants[0]==android.content.pm.PackageManager.PERMISSION_GRANTED){prefs.edit().putBoolean("notifications",true).apply();startReminder();}}
 private void failure(){if(isFinishing()||isDestroyed())return;new AlertDialog.Builder(this).setTitle("暂时连接不到电脑").setMessage("连接地址："+address+"\n请确认电脑没有休眠，G-Collie 服务与内置网络正在运行。正式服务端口为 4310。若已显示配对页，网络已接通，只需输入电脑生成的 G-Collie 配对码。").setPositiveButton("重试",(d,w)->connect(address)).setNeutralButton("内置网络",(d,w)->networkPanel()).setNegativeButton("修改地址",(d,w)->settings()).show();}
 @Override public void onBackPressed(){if(web!=null&&web.canGoBack())web.goBack();else super.onBackPressed();}
 @Override protected void onPause(){super.onPause();saveCookies();CookieManager.getInstance().flush();}
 @Override protected void onDestroy(){generation++;if(fileCallback!=null){fileCallback.onReceiveValue(null);fileCallback=null;}ui.removeCallbacksAndMessages(null);worker.shutdownNow();if(web!=null)web.destroy();super.onDestroy();}
}
