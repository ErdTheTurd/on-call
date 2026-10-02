package com.eporthospine.mdshift.ui

import com.eporthospine.mdshift.data.AccountBook
import com.eporthospine.mdshift.data.AuthCoordinator
import com.eporthospine.mdshift.data.AuthGate
import com.eporthospine.mdshift.data.FakeApi
import com.eporthospine.mdshift.data.ShiftBoard
import com.eporthospine.mdshift.domain.DoctorProfile
import com.eporthospine.mdshift.domain.StoredSession
import com.eporthospine.mdshift.domain.UserRole
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class RootViewModelTest {
    private val dispatcher = StandardTestDispatcher()

    @Before
    fun setUp() {
        Dispatchers.setMain(dispatcher)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun exploreFromTheViewModelDoesNotAttachASession() {
        val book = AccountBook()
        val api = FakeApi()
        val auth = AuthCoordinator(api, book, demoEnabled = true, allowNpiBypass = false) {}
        val board = ShiftBoard(api, book)
        val viewModel = RootViewModel(auth, board, book, demoEnabled = true)
        viewModel.explore(UserRole.Hospital)
        val gate = viewModel.authState.value.gate as AuthGate.Ready
        assertTrue(gate.explore)
        assertTrue(book.current.session == null)
        assertTrue(book.current.board.tokens.any { it.doctorName == "Maya Ellison" })
        assertFalse(book.current.board.shifts.isEmpty())
    }

    @Test
    fun releaseViewModelRefusesExplore() {
        val book = AccountBook()
        val api = FakeApi()
        val auth = AuthCoordinator(api, book, demoEnabled = false, allowNpiBypass = false) {}
        val viewModel = RootViewModel(auth, ShiftBoard(api, book), book, demoEnabled = false)
        viewModel.explore(UserRole.Doctor)
        assertTrue(viewModel.authState.value.gate is AuthGate.LoggedOut)
        assertTrue(book.current.board.shifts.isEmpty())
    }

    @Test
    fun coldStartHydratesAndSyncsBeforeTheInterval() {
        val book = AccountBook()
        val api = FakeApi()
        api.doctorComplete = true
        book.update {
            it.copy(
                session = StoredSession("doctor-1", "a@b.org", "token", "refresh", "doctor", emailConfirmed = true),
                doctor = DoctorProfile("doctor-1", "doctor-1", "", "", "MD", ""),
            )
        }
        val board = ShiftBoard(api, book)
        val auth = AuthCoordinator(api, book, demoEnabled = false, allowNpiBypass = false, sync = board::sync)
        val viewModel = RootViewModel(auth, board, book, demoEnabled = false)
        dispatcher.scheduler.runCurrent()
        assertTrue(viewModel.authState.value.gate is AuthGate.Ready)
        assertEquals("Jordan", book.current.doctor?.firstName)
        assertTrue(api.gets.any { it.contains("date=gte.") && it.contains("order=date.asc,id.asc") })
    }
}
