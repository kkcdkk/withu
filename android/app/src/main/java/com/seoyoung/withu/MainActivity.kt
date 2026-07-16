package com.seoyoung.withu

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.Composable
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.seoyoung.withu.ui.GenerateScreen
import com.seoyoung.withu.ui.HomeScreen
import com.seoyoung.withu.ui.theme.WithuTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            WithuTheme {
                WithuNav()
            }
        }
    }
}

@Composable
private fun WithuNav() {
    val nav = rememberNavController()
    NavHost(navController = nav, startDestination = "home") {
        composable("home") {
            HomeScreen(onOpenGenerate = { nav.navigate("generate") })
        }
        composable("generate") {
            GenerateScreen(onDone = { nav.popBackStack() })
        }
    }
}
