package com.eporthospine.mdshift

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.lifecycle.lifecycleScope
import com.eporthospine.mdshift.ui.MdShiftRoot
import com.eporthospine.mdshift.ui.MdShiftTheme
import com.eporthospine.mdshift.ui.RootViewModel
import com.eporthospine.mdshift.ui.googleIdToken
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private val graph by lazy { (application as MdShiftApplication).graph }
    private val viewModel: RootViewModel by viewModels {
        RootViewModel.factory(graph.auth, graph.board, graph.book, graph.demoEnabled)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            val account by viewModel.account.collectAsState()
            MdShiftTheme(account.appearance) {
                MdShiftRoot(
                    viewModel = viewModel,
                    onGoogle = { role ->
                        lifecycleScope.launch {
                            runCatching { googleIdToken(this@MainActivity, graph.googleWebClientId) }
                                .onSuccess { viewModel.signInWithGoogle(it, role) }
                                .onFailure { viewModel.report(it.message ?: "Google sign-in was cancelled.") }
                        }
                    },
                    onApple = { role ->
                        val url = viewModel.appleUrl(role)
                        CustomTabsIntent.Builder().build().launchUrl(this, Uri.parse(url))
                    },
                    onOpenUrl = { url ->
                        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                    },
                )
            }
        }
        if (savedInstanceState == null) handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        val data = intent?.data ?: return
        if (data.scheme != "mdshift") return
        when (data.host) {
            "auth-callback" -> viewModel.completeOAuth(data.toString())
            "demo" -> if (graph.demoEnabled) {
                val role = if (data.path == "/hospital") {
                    com.eporthospine.mdshift.domain.UserRole.Hospital
                } else {
                    com.eporthospine.mdshift.domain.UserRole.Doctor
                }
                viewModel.explore(role)
            }
        }
    }
}
