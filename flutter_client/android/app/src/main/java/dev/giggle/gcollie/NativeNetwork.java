package dev.giggle.gcollie;
public final class NativeNetwork {
 static { System.loadLibrary("gcollie_network"); }
 public static native String configureNetwork(String state);
 public static native String start(String directory);
 public static native String status();
 public static native String login();
 public static native String open(String remote);
 public static native String logout();
 public static native void stop();
}
