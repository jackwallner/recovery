package com.jackwallner.recovery.data

import androidx.health.connect.client.records.ExerciseSessionRecord as Exercise

import com.jackwallner.recovery.model.WorkoutClassifier

object AndroidWorkoutTypes {
    val names=mapOf(
        Exercise.EXERCISE_TYPE_BADMINTON to "badminton",Exercise.EXERCISE_TYPE_BASEBALL to "baseball",Exercise.EXERCISE_TYPE_BASKETBALL to "basketball",
        Exercise.EXERCISE_TYPE_BIKING to "cycling",Exercise.EXERCISE_TYPE_BIKING_STATIONARY to "cycling",Exercise.EXERCISE_TYPE_BOOT_CAMP to "crossTraining",
        Exercise.EXERCISE_TYPE_BOXING to "boxing",Exercise.EXERCISE_TYPE_CALISTHENICS to "functionalStrengthTraining",Exercise.EXERCISE_TYPE_CRICKET to "cricket",
        Exercise.EXERCISE_TYPE_DANCING to "dance",Exercise.EXERCISE_TYPE_ELLIPTICAL to "elliptical",Exercise.EXERCISE_TYPE_EXERCISE_CLASS to "mixedMetabolicCardioTraining",
        Exercise.EXERCISE_TYPE_FENCING to "fencing",Exercise.EXERCISE_TYPE_FOOTBALL_AMERICAN to "americanFootball",Exercise.EXERCISE_TYPE_FOOTBALL_AUSTRALIAN to "australianFootball",
        Exercise.EXERCISE_TYPE_FRISBEE_DISC to "discSports",Exercise.EXERCISE_TYPE_GOLF to "golf",Exercise.EXERCISE_TYPE_GUIDED_BREATHING to "mindAndBody",
        Exercise.EXERCISE_TYPE_GYMNASTICS to "gymnastics",Exercise.EXERCISE_TYPE_HANDBALL to "handball",Exercise.EXERCISE_TYPE_HIGH_INTENSITY_INTERVAL_TRAINING to "highIntensityIntervalTraining",
        Exercise.EXERCISE_TYPE_HIKING to "hiking",Exercise.EXERCISE_TYPE_ICE_HOCKEY to "hockey",Exercise.EXERCISE_TYPE_ICE_SKATING to "skatingSports",
        Exercise.EXERCISE_TYPE_MARTIAL_ARTS to "martialArts",Exercise.EXERCISE_TYPE_PADDLING to "paddleSports",Exercise.EXERCISE_TYPE_PILATES to "pilates",
        Exercise.EXERCISE_TYPE_RACQUETBALL to "racquetball",Exercise.EXERCISE_TYPE_ROCK_CLIMBING to "climbing",Exercise.EXERCISE_TYPE_ROLLER_HOCKEY to "hockey",
        Exercise.EXERCISE_TYPE_ROWING to "rowing",Exercise.EXERCISE_TYPE_ROWING_MACHINE to "rowing",Exercise.EXERCISE_TYPE_RUGBY to "rugby",
        Exercise.EXERCISE_TYPE_RUNNING to "running",Exercise.EXERCISE_TYPE_RUNNING_TREADMILL to "running",Exercise.EXERCISE_TYPE_SAILING to "sailing",
        Exercise.EXERCISE_TYPE_SCUBA_DIVING to "underwaterDiving",Exercise.EXERCISE_TYPE_SKATING to "skatingSports",Exercise.EXERCISE_TYPE_SKIING to "snowSports",
        Exercise.EXERCISE_TYPE_SNOWBOARDING to "snowboarding",Exercise.EXERCISE_TYPE_SNOWSHOEING to "snowSports",Exercise.EXERCISE_TYPE_SOCCER to "soccer",
        Exercise.EXERCISE_TYPE_SOFTBALL to "softball",Exercise.EXERCISE_TYPE_SQUASH to "squash",Exercise.EXERCISE_TYPE_STAIR_CLIMBING to "stairClimbing",
        Exercise.EXERCISE_TYPE_STAIR_CLIMBING_MACHINE to "stairs",Exercise.EXERCISE_TYPE_STRENGTH_TRAINING to "traditionalStrengthTraining",Exercise.EXERCISE_TYPE_STRETCHING to "flexibility",
        Exercise.EXERCISE_TYPE_SURFING to "surfingSports",Exercise.EXERCISE_TYPE_SWIMMING_OPEN_WATER to "swimming",Exercise.EXERCISE_TYPE_SWIMMING_POOL to "swimming",
        Exercise.EXERCISE_TYPE_TABLE_TENNIS to "tableTennis",Exercise.EXERCISE_TYPE_TENNIS to "tennis",Exercise.EXERCISE_TYPE_VOLLEYBALL to "volleyball",
        Exercise.EXERCISE_TYPE_WALKING to "walking",Exercise.EXERCISE_TYPE_WATER_POLO to "waterPolo",Exercise.EXERCISE_TYPE_WEIGHTLIFTING to "traditionalStrengthTraining",Exercise.EXERCISE_TYPE_YOGA to "yoga"
    )
    fun code(type: Int)=names[type]?.let(WorkoutClassifier::code)?:9999
}
