package com.eporthospine.mdshift

import android.app.Application
import android.content.Context
import com.eporthospine.mdshift.data.AccountBook
import com.eporthospine.mdshift.data.AccountPersistence
import com.eporthospine.mdshift.data.AccountState
import com.eporthospine.mdshift.data.AppConfig
import com.eporthospine.mdshift.data.AppJson
import com.eporthospine.mdshift.data.AuthCoordinator
import com.eporthospine.mdshift.data.KtorSupabaseApi
import com.eporthospine.mdshift.data.ShiftBoard
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class MdShiftApplication : Application() {
    lateinit var graph: AppGraph
        private set

    override fun onCreate() {
        super.onCreate()
        val persistence = PrefsAccountPersistence(this)
        val book = AccountBook(persistence.read())
        val api = KtorSupabaseApi.create(AppConfig.SUPABASE_URL, AppConfig.SUPABASE_ANON_KEY)
        val board = ShiftBoard(api, book)
        val demo = BuildConfig.DEMO_ENABLED
        val auth = AuthCoordinator(
            api = api,
            book = book,
            demoEnabled = demo,
            allowNpiBypass = BuildConfig.DEBUG,
            sync = board::sync,
        )
        graph = AppGraph(book, auth, board, demo, BuildConfig.GOOGLE_WEB_CLIENT_ID)
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            book.state.collect { persistence.write(it) }
        }
    }
}

data class AppGraph(
    val book: AccountBook,
    val auth: AuthCoordinator,
    val board: ShiftBoard,
    val demoEnabled: Boolean,
    val googleWebClientId: String,
)

class PrefsAccountPersistence(context: Context) : AccountPersistence {
    private val prefs = context.getSharedPreferences("mdshift_account", Context.MODE_PRIVATE)

    override fun read(): AccountState {
        val raw = prefs.getString(KEY, null) ?: return AccountState()
        return runCatching { AppJson.decodeFromString(AccountState.serializer(), raw) }.getOrDefault(AccountState())
    }

    override fun write(state: AccountState) {
        prefs.edit().putString(KEY, AppJson.encodeToString(AccountState.serializer(), state)).apply()
    }

    private companion object {
        const val KEY = "state"
    }
}
