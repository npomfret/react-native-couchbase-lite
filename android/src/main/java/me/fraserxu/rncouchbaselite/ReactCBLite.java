package me.fraserxu.rncouchbaselite;

import android.net.Uri;
import android.os.AsyncTask;

import com.couchbase.lite.Attachment;
import com.couchbase.lite.CouchbaseLiteException;
import com.couchbase.lite.Database;
import com.couchbase.lite.Document;
import com.couchbase.lite.Manager;
import com.couchbase.lite.Revision;
import com.couchbase.lite.View;
import com.couchbase.lite.android.AndroidContext;
import com.couchbase.lite.javascript.JavaScriptReplicationFilterCompiler;
import com.couchbase.lite.javascript.JavaScriptViewCompiler;
import com.couchbase.lite.listener.Credentials;
import com.couchbase.lite.listener.LiteListener;
import com.couchbase.lite.replicator.Replication;
import com.couchbase.lite.util.IOUtils;
import com.couchbase.lite.util.Log;
import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.bridge.WritableNativeMap;
import com.facebook.react.modules.core.DeviceEventManagerModule;
import com.facebook.react.uimanager.events.RCTEventEmitter;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.MalformedURLException;
import java.net.URL;
import java.net.URLConnection;
import java.security.AccessControlContext;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Properties;
import java.util.UUID;

import Acme.Serve.Serve;

import static java.security.AccessController.getContext;
import static me.fraserxu.rncouchbaselite.ReactNativeJson.convertJsonToMap;

public class ReactCBLite extends ReactContextBaseJavaModule implements Replication.ChangeListener {

    static {
        setLogLevel(Log.WARN);
    }

    public static final String REACT_CLASS = "ReactCBLite";
    private static final String TAG = "ReactCBLite";
    private static final int SUGGESTED_PORT = 5984;
    private ReactApplicationContext context;
    private Manager manager;
    private Credentials allowedCredentials;
    private LiteListener listener;

    public ReactCBLite(ReactApplicationContext reactContext) {
        super(reactContext);
        this.context = reactContext;
    }

    @Override
    public String getName() {
        return REACT_CLASS;
    }

    @ReactMethod
    public static void logLevel(String name, Promise promise) {
        switch (name) {
            case "VERBOSE": {
                setLogLevel(Log.VERBOSE);
                break;
            }
            case "DEBUG": {
                setLogLevel(Log.DEBUG);
                break;
            }
            case "INFO": {
                setLogLevel(Log.INFO);
                break;
            }
            case "WARN": {
                setLogLevel(Log.WARN);
                break;
            }
            case "ERROR": {
                setLogLevel(Log.ERROR);
                break;
            }
            case "ASSERT":
                setLogLevel(Log.ASSERT);
        }

        promise.resolve(null);
    }

    @ReactMethod
    public void init(ReadableMap options, Promise promise) {
        String username = UUID.randomUUID().toString();
        if (options.hasKey("username"))
            username = options.getString("username");

        String password = UUID.randomUUID().toString();
        if (options.hasKey("password"))
            password = options.getString("password");

        Credentials credentials;
        if (username == null && password == null) {
            credentials = null;
            Log.w(TAG, "No credential specified, your listener is unsecured and you are putting your data at risk");
        } else if (username == null || password == null) {
            promise.reject("cbl error", "invalid options, username and password must both be non-null values OR must both be null values");
            return;
        } else {
            credentials = new Credentials(username, password);
        }

        this.initWithCredentials(credentials, promise);
    }

    private void initWithCredentials(Credentials credentials, Promise promise) {
        this.allowedCredentials = credentials;

        try {
            View.setCompiler(new JavaScriptViewCompiler());
            Database.setFilterCompiler(new JavaScriptReplicationFilterCompiler());

            AndroidContext context = new AndroidContext(this.context);

            manager = new Manager(context, Manager.DEFAULT_OPTIONS);

            this._startListener();

            WritableMap response = new WritableNativeMap();
            response.putInt("listenerPort", listener.getListenPort());
            response.putString("listenerHost", "localhost");
            response.putString("listenerUrl", String.format("http://localhost:%d/", listener.getListenPort()));
            if (credentials != null) {
                response.putString("listenerUrlWithAuth", String.format("http://%s:%s@localhost:%d/", credentials.getLogin(), credentials.getPassword(), listener.getListenPort()));
                response.putString("username", credentials.getLogin());
                response.putString("password", credentials.getPassword());
            }
            promise.resolve(response);

        } catch (final Exception e) {
            Log.e(TAG, "Couchbase init failed", e);
            promise.reject("cbl error", e);
        }
    }

    private static void setLogLevel(int level) {
        Log.i(TAG, "Setting log level to '" + level + "'");

        Manager.enableLogging(Log.TAG, level);
        Manager.enableLogging(Log.TAG_SYNC, level);
        Manager.enableLogging(Log.TAG_BATCHER, level);
        Manager.enableLogging(Log.TAG_SYNC_ASYNC_TASK, level);
        Manager.enableLogging(Log.TAG_REMOTE_REQUEST, level);
        Manager.enableLogging(Log.TAG_VIEW, level);
        Manager.enableLogging(Log.TAG_QUERY, level);
        Manager.enableLogging(Log.TAG_CHANGE_TRACKER, level);
        Manager.enableLogging(Log.TAG_ROUTER, level);
        Manager.enableLogging(Log.TAG_DATABASE, level);
        Manager.enableLogging(Log.TAG_LISTENER, level);
        Manager.enableLogging(Log.TAG_MULTI_STREAM_WRITER, level);
        Manager.enableLogging(Log.TAG_BLOB_STORE, level);
        Manager.enableLogging(Log.TAG_SYMMETRIC_KEY, level);
        Manager.enableLogging(Log.TAG_ACTION, level);
    }

    /*
        use this regexp in android studio
        CBLite|Sync|Batcher|SyncAsyncTask|RemoteRequest|View|Query|ChangeTracker|Router|Database|Listener|MultistreamWriter|BlobStore|SymmetricKey|Action
    */

    @ReactMethod
    public void stopListener(Promise promise) {
        Log.i(TAG, "Stopping CBL listener on port " + listener.getListenPort());
        listener.stop();
        promise.resolve(null);
    }

    @ReactMethod
    public void startListener(Promise promise) {
        _startListener();
        promise.resolve(null);
    }

    private void _startListener() {
        if (listener == null) {
            if (allowedCredentials == null) {
                Log.i(TAG, "No credentials, so binding to localhost");
                Properties props = new Properties();
                props.put(Serve.ARG_BINDADDRESS, "localhost");
                listener = new LiteListener(manager, SUGGESTED_PORT, allowedCredentials, props);
            } else {
                listener = new LiteListener(manager, SUGGESTED_PORT, allowedCredentials);
            }

            Log.i(TAG, "Starting CBL listener on port " + listener.getListenPort());
        } else {
            Log.i(TAG, "Restarting CBL listener on port " + listener.getListenPort());
        }

        listener.start();
    }

    @ReactMethod
    public void startContinuousReplication(String databaseName, String url, ReadableMap options, Promise promise) {
        try {
            Database database = manager.getDatabase(databaseName);

            URL remoteUrl = new URL(url);

            boolean isPull = isPull(options.getString("type"));

            for (Replication replication : database.getAllReplications()) {
                if (replication.isContinuous()&& replication.getRemoteUrl().equals(remoteUrl)) {
                    if (replication.isPull() && isPull) {
                        Log.i(TAG, "replication already exists");
                        promise.resolve(null);
                        return;
                    } else if (!replication.isPull() && !isPull) {
                        Log.i(TAG, "replication already exists");
                        promise.resolve(null);
                        return;
                    }
                }
            }

            Replication repl = isPull ? database.createPullReplication(remoteUrl) : database.createPushReplication(remoteUrl);

            String sessionId = options.getString("sessionId");

            String cookieName = "SyncGatewaySession";
            if (options.hasKey("cookieName"))
                cookieName = options.getString("cookieName");

            boolean secure = false;
            if (options.hasKey("secure"))
                secure = options.getBoolean("secure");

            repl.setContinuous(true);
            repl.setCookie(cookieName, sessionId, null, null, secure, true);

            repl.addChangeListener(this);

            repl.start();

            promise.resolve(null);
        } catch (Exception e) {
            promise.reject("cbl error", "Failed to startContinuousReplication", e);
        }
    }

    @ReactMethod
    public void stopContinuousReplication(String databaseName, String pushOrPull, Promise promise) {
        try {
            Database database = manager.getDatabase(databaseName);

            boolean isPull = isPull(pushOrPull);

            for (Replication replication : database.getAllReplications()) {
                if (replication.isContinuous()) {
                    if (replication.isPull() && isPull) {
                        Log.i(TAG, "stopping replication");
                        replication.stop();
                        replication.removeChangeListener(this);
                    } else if (!replication.isPull() && !isPull) {
                        Log.i(TAG, "stopping replication");
                        replication.stop();
                        replication.removeChangeListener(this);
                    }
                }
            }

            promise.resolve(null);
        } catch (Exception e) {
            promise.reject("cbl error", "Failed to stopContinuousReplication", e);
        }
    }

    @ReactMethod
    public void suspendContinuousReplications(String databaseName, String pushOrPull, Promise promise) {
        try {
            Database database = manager.getDatabase(databaseName);

            boolean isPull = isPull(pushOrPull);

            for (Replication replication : findContinuousReplications(database, isPull)) {
                Log.i(TAG, "suspending replication");
                replication.goOffline();
            }

            promise.resolve(null);
        } catch (Exception e) {
            promise.reject("cbl error", "Failed to stopContinuousReplication", e);
        }
    }

    @ReactMethod
    public void resumeContinuousReplications(String databaseName, String pushOrPull, Promise promise) {
        try {
            Database database = manager.getDatabase(databaseName);

            boolean isPull = isPull(pushOrPull);

            for (Replication replication : findContinuousReplications(database, isPull)) {
                Log.i(TAG, "suspending replication");
                replication.goOnline();
            }

            promise.resolve(null);
        } catch (Exception e) {
            promise.reject("cbl error", "Failed to stopContinuousReplication", e);
        }
    }

    @Override
    public void changed(Replication.ChangeEvent event) {
        WritableMap nativeEvent = Arguments.createMap();

        Replication source = event.getSource();
        nativeEvent.putString("type", source.isPull() ? "pull" : "push");
        nativeEvent.putInt("changesCount", event.getChangeCount());
        nativeEvent.putInt("completedChangesCount", event.getCompletedChangeCount());
        nativeEvent.putBoolean("running", source.isRunning());
        nativeEvent.putString("status", event.getStatus().name());
        nativeEvent.putBoolean("suspended", source.isRunning());
        nativeEvent.putString("lastErrorCode", event.getError() == null ? "" : event.getError().getMessage());

        context.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter.class)
                .emit("replicationChanged", nativeEvent);
    }

    @ReactMethod
    public void copyAttachment(String databaseName, String id, String attachmentName, String path, Promise promise) {
        try {
            Database database = manager.getDatabase(databaseName);

            Document doc = database.getDocument(id);
            Revision rev = doc.getCurrentRevision();
            Attachment att = rev.getAttachment(attachmentName);
            if (att != null) {
                copy(att, path);
            }
        } catch (Exception e) {
            promise.reject("cbl error", "Failed to copy attachment", e);
        }
    }

    @ReactMethod
    public void upload(String method, String authHeader, String sourceUri, String targetUri, String contentType, Promise promise) {
        if (method == null || !method.toUpperCase().equals("PUT")) {
            promise.reject("cbl error", "Bad parameter method: " + method);
            return;
        }
        if (authHeader == null) {
            promise.reject("cbl error", "Bad parameter authHeader");
            return;
        }
        if (sourceUri == null) {
            promise.reject("cbl error", "Bad parameter sourceUri");
            return;
        }
        if (targetUri == null) {
            promise.reject("cbl error", "Bad parameter targetUri");
            return;
        }
        if (contentType == null) {
            promise.reject("cbl error", "Bad parameter contentType");
            return;
        }

        SaveAttachmentTask saveAttachmentTask = new SaveAttachmentTask(method, authHeader, sourceUri, targetUri, contentType, promise);
        saveAttachmentTask.execute();
    }

    private class SaveAttachmentTask extends AsyncTask<URL, Integer, UploadResult> {
        private final String method;
        private final String authHeader;
        private final String sourceUri;
        private final String targetUri;
        private final String contentType;
        private final Promise promise;

        private SaveAttachmentTask(String method, String authHeader, String sourceUri, String targetUri, String contentType, Promise promise) {
            this.method = method;
            this.authHeader = authHeader;
            this.sourceUri = sourceUri;
            this.targetUri = targetUri;
            this.contentType = contentType;
            this.promise = promise;
        }

        @Override
        protected UploadResult doInBackground(URL... params) {
            try {
                Log.i(TAG, "Uploading attachment '" + sourceUri + "' to '" + targetUri + "'");

                InputStream input;
                if (sourceUri.startsWith("/") || sourceUri.startsWith("file:/")) {
                    String path = sourceUri.replace("file://", "/")
                            .replace("file:/", "/");
                    File file = new File(path);

                    input = new FileInputStream(file);
                } else if (sourceUri.startsWith("content://")) {
                    input = ReactCBLite.this.context.getContentResolver().openInputStream(Uri.parse(sourceUri));
                } else {
                    URLConnection urlConnection = new URL(sourceUri).openConnection();
                    input = urlConnection.getInputStream();
                }

                try {
                    HttpURLConnection conn = (HttpURLConnection) new URL(targetUri).openConnection();
                    conn.setRequestProperty("Content-Type", contentType);
                    conn.setRequestProperty("Authorization", authHeader);
                    conn.setReadTimeout(100000);
                    conn.setConnectTimeout(100000);
                    conn.setRequestMethod(method);
                    conn.setDoInput(true);
                    conn.setDoOutput(true);

                    OutputStream os = conn.getOutputStream();
                    try {
                        byte[] buffer = new byte[1024];
                        int bytesRead;
                        while ((bytesRead = input.read(buffer)) != -1) {
                            os.write(buffer, 0, bytesRead);
                            publishProgress(bytesRead);
                        }
                    } finally {
                        os.close();
                    }

                    int responseCode = conn.getResponseCode();

                    StringBuilder responseText = new StringBuilder();
                    BufferedReader br = new BufferedReader(new InputStreamReader(conn.getInputStream()));
                    try {
                        String line;
                        while ((line = br.readLine()) != null) {
                            responseText.append(line);
                        }
                    } finally {
                        br.close();
                    }

                    return new UploadResult(responseCode, responseText.toString());
                } finally {
                    input.close();
                }
            } catch (Exception e) {
                Log.e(TAG, "Failed to save attachment", e);
                return new UploadResult(-1, "Failed to save attachment " + e.getMessage());
            }
        }

        @Override
        protected void onProgressUpdate(Integer... values) {
            Log.d(TAG, "Uploaded", Arrays.toString(values));
        }

        @Override
        protected void onPostExecute(UploadResult uploadResult) {
            int responseCode = uploadResult.statusCode;
            WritableMap map = Arguments.createMap();
            map.putInt("statusCode", responseCode);

            if (responseCode == 200 || responseCode == 202) {
                try {
                    JSONObject jsonObject = new JSONObject(uploadResult.response);
                    map.putMap("resp", convertJsonToMap(jsonObject));
                    promise.resolve(map);
                } catch (JSONException e) {
                    promise.reject("cbl error", uploadResult.response);
                    Log.e(TAG, "Failed to parse response from clb: " + uploadResult.response, e);
                }
            } else {
                promise.reject("cbl error", uploadResult.response);
            }
        }
    }

    private static class UploadResult {
        public final int statusCode;
        public final String response;

        public UploadResult(int statusCode, String response) {
            this.statusCode = statusCode;
            this.response = response;
        }
    }

    private static Iterable<Replication> findContinuousReplications(Database database, boolean isPull) {
        List<Replication> matching = new ArrayList<>();
        for (Replication replication : database.getAllReplications()) {
            if(!replication.isContinuous())
                continue;

            if(isPull && replication.isPull())
                matching.add(replication);

            if(!isPull && !replication.isPull())
                matching.add(replication);
        }

        return matching;
    }

    private static boolean isPull(String pushOrPull) {
        if (pushOrPull.equals("pull"))
            return true;
        else if (pushOrPull.equals("push"))
            return false;
        else
            throw new IllegalStateException("invalid type: " + pushOrPull);
    }

    private static void copy(Attachment att, String path) throws CouchbaseLiteException, IOException {
        InputStream in = att.getContent();
        try {
            FileOutputStream out = new FileOutputStream(path);
            try {
                IOUtils.copy(in, out);
            } finally {
                out.close();
            }
        } finally {
            in.close();
        }
    }
}
