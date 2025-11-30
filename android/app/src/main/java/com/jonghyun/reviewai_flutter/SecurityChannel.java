package com.jonghyun.reviewai_flutter;

import android.content.Context;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.util.Base64;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Arrays;

public class SecurityChannel implements MethodCallHandler {
    private static final String CHANNEL = "security_channel";
    
    private static final String EXPECTED_SIGNATURE_HASH = "U6c9L3biD2/0HQTuMBqjjbwO2lKLwgfaorW/mFEWvUU=";

    private final Context context;

    public SecurityChannel(Context context) {
        this.context = context;
    }

    public static void registerWith(FlutterEngine flutterEngine, Context context) {
        final MethodChannel channel = new MethodChannel(
            flutterEngine.getDartExecutor().getBinaryMessenger(),
            CHANNEL
        );
        channel.setMethodCallHandler(new SecurityChannel(context));
    }

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        if (call.method.equals("verifySignature")) {
            result.success(verifyAppSignature());
        } else {
            result.notImplemented();
        }
    }

    private boolean verifyAppSignature() {
        try {
            PackageInfo packageInfo;
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                packageInfo = context.getPackageManager()
                    .getPackageInfo(context.getPackageName(), PackageManager.GET_SIGNING_CERTIFICATES);
                
                android.content.pm.SigningInfo signingInfo = packageInfo.signingInfo;
                if (signingInfo.hasMultipleSigners()) {
                    for (Signature signature : signingInfo.getApkContentsSigners()) {
                        if (checkSignature(signature)) return true;
                    }
                } else {
                    for (Signature signature : signingInfo.getSigningCertificateHistory()) {
                        if (checkSignature(signature)) return true;
                    }
                }
            } else {
                packageInfo = context.getPackageManager()
                    .getPackageInfo(context.getPackageName(), PackageManager.GET_SIGNATURES);

                for (Signature signature : packageInfo.signatures) {
                    if (checkSignature(signature)) return true;
                }
            }
        } catch (PackageManager.NameNotFoundException | NoSuchAlgorithmException e) {
            e.printStackTrace();
            return false;
        }
        return false;
    }

    private boolean checkSignature(Signature signature) throws NoSuchAlgorithmException {
        String signatureHash = getSHA256Hash(signature.toByteArray());
        return EXPECTED_SIGNATURE_HASH.equals(signatureHash);
    }

    private String getSHA256Hash(byte[] bytes) throws NoSuchAlgorithmException {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        byte[] hash = digest.digest(bytes);
        return Base64.encodeToString(hash, Base64.NO_WRAP);
    }
}