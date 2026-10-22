package dev.giggle.gcollie;
final class NativeNetwork {
 static { System.loadLibrary("gcollie_network"); }
 static native String configureNetwork(String state);
 static native String start(String directory);
 static native String status();
 static native String login();
 static native String open(String remote);
 static native String logout();
 static native void stop();
}
