package com.jackwallner.recovery.model

import org.json.JSONArray
import org.json.JSONObject

object AppContent {
    private val root by lazy{JSONObject(checkNotNull(javaClass.getResourceAsStream("/app-content.json")).bufferedReader().use{it.readText()})}
    val announcementVersion get()=root.getString("announcementVersion")
    val updates get()=pairs(root.getJSONArray("updates"))
    val features get()=pairs(root.getJSONArray("features"))
    fun questionTitle(key: String)=root.getJSONObject("questions").getJSONObject(key).getString("title")
    fun questionDetail(key: String)=root.getJSONObject("questions").getJSONObject(key).getString("detail")
    private fun pairs(array: JSONArray)=(0 until array.length()).map{val row=array.getJSONObject(it);row.getString("title") to row.getString("detail")}
}
