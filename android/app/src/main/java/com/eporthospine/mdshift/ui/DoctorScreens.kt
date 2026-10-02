package com.eporthospine.mdshift.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.eporthospine.mdshift.data.AccountState
import com.eporthospine.mdshift.domain.EscalationCurve
import com.eporthospine.mdshift.domain.PenaltyCalculator
import com.eporthospine.mdshift.domain.RosterDoctor
import com.eporthospine.mdshift.domain.SchedulingAction
import com.eporthospine.mdshift.domain.Shift
import com.eporthospine.mdshift.domain.TradeRequest
import com.eporthospine.mdshift.data.utcDate
import com.eporthospine.mdshift.domain.hoursUntil
import java.text.NumberFormat
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneOffset
import java.util.Locale

private fun money(value: Double): String = NumberFormat.getCurrencyInstance(Locale.US).format(value)

@Composable
fun DoctorApp(
    account: AccountState,
    now: Long,
    onSignOut: () -> Unit,
    onRequest: (Shift) -> Unit,
    onAccept: (Shift) -> Unit,
    onCancel: (Shift) -> Unit,
    onTrade: (Shift, RosterDoctor, Shift, Double) -> Unit,
    onRespond: (TradeRequest, Boolean) -> Unit,
    onCounter: (TradeRequest, Shift, Double) -> Unit,
    onRetrySync: () -> Unit,
    onAppearance: (String) -> Unit,
    onToggleHospital: (String) -> Unit,
    onNotify: (newShifts: Boolean, trades: Boolean, approvals: Boolean) -> Unit,
    onPrivacy: () -> Unit,
    onSupport: () -> Unit,
    message: String?,
) {
    var tab by rememberSaveable { mutableStateOf("home") }
    var month by rememberSaveable { mutableStateOf(YearMonth.now().toString()) }
    var selected by rememberSaveable { mutableStateOf<String?>(null) }
    var showSettings by rememberSaveable { mutableStateOf(false) }
    val ym = YearMonth.parse(month)
    val board = account.board
    val me = account.session?.userId ?: account.doctor?.userId
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (board.explore) SampleBanner()
            board.syncError?.let { SyncBanner(it, onRetrySync) }
            message?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            when (tab) {
                "shifts" -> MyShifts(account, now, onCancel, onTrade, onRespond, onCounter)
                "credentials" -> Credentials(account)
                else -> DoctorHome(account, ym, selected, now, { month = it.toString() }, { selected = it.toString() }, { showSettings = true }, onRequest, onAccept)
            }
            if (showSettings) DoctorSettings(account, onSignOut, onAppearance, onToggleHospital, onNotify, onPrivacy, onSupport) { showSettings = false }
        }
        val incoming = board.trades.count { it.toDoctorId == me && it.state == "pending" }
        NavigationBar {
            NavigationBarItem(tab == "home", { tab = "home" }, label = { Text("Home") }, icon = { Text("•") })
            NavigationBarItem(tab == "shifts", { tab = "shifts" }, label = { Text(if (incoming > 0) "My Shifts ($incoming)" else "My Shifts") }, icon = { Text("•") })
            NavigationBarItem(tab == "credentials", { tab = "credentials" }, label = { Text("Credentials") }, icon = { Text("•") })
        }
    }
}

@Composable
private fun DoctorHome(
    account: AccountState,
    month: YearMonth,
    selected: String?,
    now: Long,
    onMonth: (YearMonth) -> Unit,
    onSelect: (LocalDate) -> Unit,
    onSettings: () -> Unit,
    onRequest: (Shift) -> Unit,
    onAccept: (Shift) -> Unit,
) {
    val profile = account.doctor
    val board = account.board
    val specialty = profile?.specialties?.firstOrNull()
    val hidden = account.hiddenHospitalIds.toSet()
    Text(profile?.displayName ?: "Doctor", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
    TextButton(onClick = onSettings) { Text("Settings") }
    if (profile != null && profile.verificationStatus != "verified") {
        Text("Verification is ${profile.verificationStatus}. You can browse. Accept opens after you are verified.")
    }
    val today = Instant.ofEpochMilli(now).atZone(ZoneOffset.UTC).toLocalDate().toString()
    val used = board.tokens.count { it.doctorId == profile?.userId && it.shiftDate == today && it.status != "denied" }
    Text("Tokens today: $used / ${board.policy.dailyTokens(profile?.userId)}")
    Row {
        StatusDot(Accent, "Yours")
        StatusDot(Success, "Open")
        StatusDot(Warning, "Requested")
    }
    MonthCalendar(
        month = month,
        dayColor = { date ->
            val key = date.toString()
            val dayShifts = board.shifts.filter { utcDate(it.startEpochMillis) == key }
            val mine = board.assignments.any { row -> row.doctorId == profile?.userId && row.status != "canceled" && dayShifts.any { it.id == row.shiftId } }
            val requested = board.tokens.any { it.doctorId == profile?.userId && it.shiftDate == key && it.status == "pending" }
            val open = dayShifts.any { shift -> shift.id !in board.filledShiftIds && board.assignments.none { it.shiftId == shift.id && it.status != "canceled" } }
            when {
                mine -> Accent
                requested -> Warning
                open -> Success
                else -> null
            }
        },
        onDay = onSelect,
        onPrev = { onMonth(month.minusMonths(1)) },
        onNext = { onMonth(month.plusMonths(1)) },
    )
    val day = selected
    if (day != null) {
        val shifts = board.shifts.filter {
            utcDate(it.startEpochMillis) == day && it.hospitalId !in hidden && (specialty == null || it.specialty == specialty)
        }
        SectionCard("Available shifts · $day") {
            if (shifts.isEmpty()) EmptyState("No open shifts this day. A hospital has not posted your specialty yet.")
            shifts.forEach { shift ->
                val filled = shift.id in board.filledShiftIds || board.assignments.any { it.shiftId == shift.id && it.status != "canceled" }
                val rate = EscalationCurve.currentRate(shift, now)
                val token = board.tokens.firstOrNull { it.doctorId == profile?.userId && it.hospitalId == shift.hospitalId && it.shiftDate == day }
                Text("${shift.hospitalName} · ${shift.specialty}")
                Text("${money(rate)} · ${EscalationCurve.urgencyLabel(hoursUntil(shift.startEpochMillis, now), shift.perDay)}")
                val mine = board.assignments.any { it.shiftId == shift.id && it.doctorId == profile?.userId && it.status != "canceled" }
                when {
                    mine -> Text("Yours")
                    filled -> Text("Filled")
                    token?.status == "approved" || token?.status == "auto_approved" -> OutlinedButton(onClick = { onAccept(shift) }) { Text("Accept shift") }
                    token?.status == "pending" -> Text("Request pending")
                    token?.status == "denied" -> Text("Request denied")
                    !filled -> OutlinedButton(onClick = { onRequest(shift) }) { Text("Request this day") }
                }
            }
        }
    }
    val recommended = board.shifts.filter { shift ->
        shift.startEpochMillis >= now && shift.hospitalId !in hidden &&
            (specialty == null || shift.specialty == specialty) &&
            shift.id !in board.filledShiftIds &&
            board.assignments.none { it.shiftId == shift.id && it.status != "canceled" }
    }.sortedBy { it.startEpochMillis }.take(5)
    SectionCard("Recommended") {
        if (recommended.isEmpty()) EmptyState("No open shifts in this window.")
        recommended.forEach { shift ->
            Text("${utcDate(shift.startEpochMillis)} · ${shift.hospitalName} · ${money(EscalationCurve.currentRate(shift, now))}")
        }
    }
}

@Composable
private fun MyShifts(
    account: AccountState,
    now: Long,
    onCancel: (Shift) -> Unit,
    onTrade: (Shift, RosterDoctor, Shift, Double) -> Unit,
    onRespond: (TradeRequest, Boolean) -> Unit,
    onCounter: (TradeRequest, Shift, Double) -> Unit,
) {
    val me = account.session?.userId ?: account.doctor?.userId
    val board = account.board
    Text("My shifts", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
    val incoming = board.trades.filter { it.toDoctorId == me && it.state == "pending" }
    incoming.forEach { trade ->
        SectionCard("Incoming · ${trade.fromDoctorName}") {
            Text("${trade.offeredDate} ↔ ${trade.requestedDate}")
            Text("Compensation ${money(trade.compensationAmount)} · ${trade.specialty}")
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = { onRespond(trade, true) }) { Text("Accept") }
                OutlinedButton(onClick = { onRespond(trade, false) }) { Text("Decline") }
            }
            val alternates = board.shifts.filter { shift ->
                board.assignments.any { it.shiftId == shift.id && it.doctorId == me && it.status != "canceled" } && shift.id != trade.requestedShiftId
            }
            var comp by rememberSaveable(trade.id) { mutableFloatStateOf(trade.compensationAmount.toFloat()) }
            if (alternates.isNotEmpty()) {
                Text("Counter with one of your days")
                Slider(comp, { comp = it }, valueRange = 0f..1000f)
                alternates.take(4).forEach { alt ->
                    OutlinedButton(onClick = { onCounter(trade, alt, comp.toDouble()) }) {
                        Text("Send counter ${utcDate(alt.startEpochMillis)}")
                    }
                }
            }
        }
    }
    val mine = board.assignments.filter { it.doctorId == me && it.status != "canceled" }
    if (mine.isEmpty()) EmptyState("You have no assigned shifts in this window.")
    mine.forEach { row ->
        val shift = board.shifts.firstOrNull { it.id == row.shiftId } ?: return@forEach
        var trading by rememberSaveable(shift.id) { mutableStateOf(false) }
        SectionCard("${utcDate(shift.startEpochMillis)} · ${shift.hospitalName}") {
            Text("${shift.specialty} · ${money(EscalationCurve.currentRate(shift, now))} · ${row.status}")
            val cancel = PenaltyCalculator.preview(SchedulingAction.Cancel, board.policy, shift.startEpochMillis, now, shift.rateFloor)
            Text(if (cancel.allowed) "Cancel fee ${money(cancel.penaltyAmount)}" else "Inside the ${cancel.windowHours}-hour cancel window")
            if (cancel.allowed) OutlinedButton(onClick = { onCancel(shift) }) { Text("Cancel shift") }
            TextButton(onClick = { trading = !trading }) { Text("Trade shift") }
            if (trading) TradePicker(account, shift, onTrade)
        }
    }
    val earnings = mine.mapNotNull { row -> board.shifts.firstOrNull { it.id == row.shiftId } }.sumOf { EscalationCurve.currentRate(it, now) }
    SectionCard("My earnings") {
        if (mine.isEmpty()) EmptyState("Earnings appear when you hold a shift.") else Text(money(earnings))
    }
}

@Composable
private fun TradePicker(account: AccountState, shift: Shift, onTrade: (Shift, RosterDoctor, Shift, Double) -> Unit) {
    val partners = account.board.roster.filter { doctor ->
        doctor.doctorId != account.doctor?.userId && (doctor.specialties.isEmpty() || shift.specialty in doctor.specialties)
    }
    var comp by rememberSaveable(shift.id) { mutableFloatStateOf(0f) }
    if (partners.isEmpty()) {
        EmptyState("No same-specialty partners are on this hospital roster yet.")
        return
    }
    Text("Compensation ${money(comp.toDouble())}")
    Slider(comp, { comp = it }, valueRange = 0f..1000f)
    partners.forEach { partner ->
        val days = account.board.shifts.filter { candidate ->
            account.board.assignments.any { it.shiftId == candidate.id && it.doctorId == partner.doctorId && it.status != "canceled" }
        }
        Text(partner.displayName)
        if (days.isEmpty()) Text("No assigned day to swap.")
        days.take(3).forEach { theirs ->
            OutlinedButton(onClick = { onTrade(shift, partner, theirs, comp.toDouble()) }) {
                Text("Offer ${utcDate(theirs.startEpochMillis)}")
            }
        }
    }
}

@Composable
private fun Credentials(account: AccountState) {
    val profile = account.doctor
    Text("Credentials", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
    if (profile == null) {
        EmptyState("Your credential record has not loaded.")
        return
    }
    SectionCard(profile.displayName) {
        Text("NPI ${profile.npi}")
        Text("License ${profile.licenseNumber} ${profile.licenseState}")
        Text(profile.email)
        Text(profile.specialties.joinToString())
        Text("Status ${profile.verificationStatus}")
        Text("NPI is checked against the public registry. MD Shift does not upload documents.")
    }
}

@Composable
private fun DoctorSettings(
    account: AccountState,
    onSignOut: () -> Unit,
    onAppearance: (String) -> Unit,
    onToggleHospital: (String) -> Unit,
    onNotify: (Boolean, Boolean, Boolean) -> Unit,
    onPrivacy: () -> Unit,
    onSupport: () -> Unit,
    onClose: () -> Unit,
) {
    SectionCard("Settings") {
        Text("Appearance")
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("System", "Light", "Dark").forEach { mode ->
                FilterChip(selected = account.appearance == mode, onClick = { onAppearance(mode) }, label = { Text(mode) })
            }
        }
        Text("Hide hospitals")
        account.board.shifts.map { it.hospitalId to it.hospitalName }.distinct().forEach { (id, name) ->
            val hidden = id in account.hiddenHospitalIds
            FilterChip(selected = hidden, onClick = { onToggleHospital(id) }, label = { Text(if (hidden) "Hidden $name" else name) })
        }
        Text("Notifications stay on this device. Remote push is not on yet.")
        FilterChip(account.notifyNewShifts, { onNotify(!account.notifyNewShifts, account.notifyTrades, account.notifyApprovals) }, label = { Text("New matching shifts") })
        FilterChip(account.notifyTrades, { onNotify(account.notifyNewShifts, !account.notifyTrades, account.notifyApprovals) }, label = { Text("Incoming trades") })
        FilterChip(account.notifyApprovals, { onNotify(account.notifyNewShifts, account.notifyTrades, !account.notifyApprovals) }, label = { Text("Approvals") })
        TextButton(onClick = onPrivacy) { Text("Privacy Policy") }
        TextButton(onClick = onSupport) { Text("Support") }
        Text("To delete your account, contact support. MD Shift does not delete accounts inside the app.")
        OutlinedButton(onClick = onSignOut, modifier = Modifier.fillMaxWidth()) { Text("Sign out") }
        TextButton(onClick = onClose) { Text("Close") }
    }
}
