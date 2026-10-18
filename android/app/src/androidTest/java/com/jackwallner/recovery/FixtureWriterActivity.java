package com.jackwallner.recovery;

import java.time.Instant;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;

import android.app.Activity;
import android.content.Intent;
import android.health.connect.HealthConnectException;
import android.health.connect.HealthConnectManager;
import android.health.connect.InsertRecordsResponse;
import android.health.connect.RecordIdFilter;
import android.health.connect.datatypes.ExerciseSegment;
import android.health.connect.datatypes.ExerciseSegmentType;
import android.health.connect.datatypes.ExerciseSessionRecord;
import android.health.connect.datatypes.ExerciseSessionType;
import android.health.connect.datatypes.HeartRateRecord;
import android.health.connect.datatypes.Metadata;
import android.health.connect.datatypes.Record;
import android.os.Bundle;
import android.os.OutcomeReceiver;

/** Standalone test APK process, using only framework APIs and its own write grants. */
public final class FixtureWriterActivity extends Activity {
    public static final String RESULT_ACTION = "com.jackwallner.recovery.FIXTURE_READY";

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        try {
            HealthConnectManager manager = getSystemService(HealthConnectManager.class);
            if ("clear".equals(getIntent().getStringExtra("operation"))) {
                manager.deleteRecords(List.of(
                    RecordIdFilter.fromClientRecordId(ExerciseSessionRecord.class, "sol-recharge-run"),
                    RecordIdFilter.fromClientRecordId(HeartRateRecord.class, "sol-recharge-heart")
                ), getMainExecutor(), new OutcomeReceiver<Void, HealthConnectException>() {
                    @Override public void onResult(Void result) { complete(null); }
                    @Override public void onError(HealthConnectException error) { complete(error); }
                });
                return;
            }
            Instant end = Instant.now().minusSeconds(3600);
            Instant start = end.minusSeconds(3600);
            ExerciseSessionRecord workout = new ExerciseSessionRecord.Builder(
                metadata("sol-recharge-run"), start, end, ExerciseSessionType.EXERCISE_SESSION_TYPE_RUNNING
            ).setStartZoneOffset(ZoneOffset.UTC).setEndZoneOffset(ZoneOffset.UTC)
                .setSegments(List.of(new ExerciseSegment.Builder(
                    start.plusSeconds(1800), start.plusSeconds(2400), ExerciseSegmentType.EXERCISE_SEGMENT_TYPE_PAUSE
                ).build())).build();
            List<HeartRateRecord.HeartRateSample> samples = new ArrayList<>();
            for (int index = 0; index < 60; index++) {
                samples.add(new HeartRateRecord.HeartRateSample(155L, start.plusSeconds(index * 60L)));
            }
            HeartRateRecord heart = new HeartRateRecord.Builder(metadata("sol-recharge-heart"), start, end, samples)
                .setStartZoneOffset(ZoneOffset.UTC).setEndZoneOffset(ZoneOffset.UTC).build();
            manager.insertRecords(List.<Record>of(workout, heart), getMainExecutor(),
                new OutcomeReceiver<InsertRecordsResponse, HealthConnectException>() {
                    @Override public void onResult(InsertRecordsResponse result) { complete(null); }
                    @Override public void onError(HealthConnectException error) { complete(error); }
                });
        } catch (Exception error) { complete(error); }
    }
    private Metadata metadata(String id) {
        return new Metadata.Builder().setClientRecordId(id).setClientRecordVersion(System.currentTimeMillis())
            .setRecordingMethod(Metadata.RECORDING_METHOD_MANUAL_ENTRY).build();
    }
    private void complete(Exception error) {
        Intent response = new Intent(RESULT_ACTION).setPackage(getPackageName().replaceFirst("\\.test$", ""))
            .putExtra("request", getIntent().getStringExtra("request"));
        if (error != null) response.putExtra("error", error.getClass().getSimpleName() + ": " + error.getMessage());
        sendBroadcast(response);
        finish();
    }
}
