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
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.eporthospine.mdshift.data.AccountState
import com.eporthospine.mdshift.data.utcDate
import com.eporthospine.mdshift.domain.RosterDoctor
import com.eporthospine.mdshift.domain.SPECIALTIES
import com.eporthospine.mdshift.domain.SchedulingPolicy
import com.eporthospine.mdshift.domain.TokenRequest
import java.text.NumberFormat
import java.time.LocalDate
import java.time.YearMonth
import java.util.Locale

private fun money(value: Double): String = NumberFormat.getCurrencyInstance(Locale.US).format(value)

@Composable
fun HospitalApp(
    account: AccountState,
    onSignOut: () -> Unit,
    onApprove: (TokenRequest) -> Unit,
    onDeny: (TokenRequest) -> Unit,
    onAutoApprove: (RosterDoctor, Boolean) -> Unit,
    onSavePolicy: (SchedulingPolicy) -> Unit,
    onPostShift: (specialty: String, dayEpoch: Long, rate: Double, algorithm: Boolean) -> Unit,
    onUnavailable: (date: String, blocked: Boolean) -> Unit,
    onRetrySync: () -> Unit,
    onAppearance: (String) -> Unit,
    onPriority: (Boolean) -> Unit,
    onAutoPay: (Boolean) -> Unit,
    onTokenLimit: (String, Int) -> Unit,
    onPrivacy: () -> Unit,
    onSupport: () -> Unit,
    message: String?,
) {
    var tab by rememberSaveable { mutableStateOf("home") }
    var sheet by rememberSaveable { mutableStateOf("none") }
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (account.board.explore) SampleBanner()
            account.board.syncError?.let { SyncBanner(it, onRetrySync) }
            message?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            when (sheet) {
                "approvals" -> Approvals(account, onApprove, onDeny) { sheet = "none" }
                "policy" -> PolicyEditor(account.board.policy, onSavePolicy) { sheet = "none" }
                "analytics" -> Analytics(account) { sheet = "none" }
                "billing" -> Billing(account) { sheet = "none" }
                "settings" -> HospitalSettings(
                    account, onSignOut, onAppearance, onPriority, onAutoPay, onPrivacy, onSupport,
                    { sheet = it }, { sheet = "none" },
                )
                else -> when (tab) {
                    "alter" -> AlterShifts(account, onPostShift, onSavePolicy)
                    "doctors" -> DoctorsTab(account, onAutoApprove, onTokenLimit)
                    else -> HospitalHome(account, onApprove, onDeny, onUnavailable) { sheet = it }
                }
            }
        }
        NavigationBar {
            NavigationBarItem(tab == "home" && sheet == "none", { tab = "home"; sheet = "none" }, label = { Text("Home") }, icon = { Text("•") })
            NavigationBarItem(tab == "alter" && sheet == "none", { tab = "alter"; sheet = "none" }, label = { Text("Alter Shifts") }, icon = { Text("•") })
            NavigationBarItem(tab == "doctors" && sheet == "none", { tab = "doctors"; sheet = "none" }, label = { Text("Doctors") }, icon = { Text("•") })
        }
        if (sheet == "none") {
            TextButton(onClick = { sheet = "settings" }, modifier = Modifier.padding(horizontal = 8.dp)) { Text("Settings") }
        }
    }
}

@Composable
private fun HospitalHome(
    account: AccountState,
    onApprove: (TokenRequest) -> Unit,
    onDeny: (TokenRequest) -> Unit,
    onUnavailable: (String, Boolean) -> Unit,
    onOpen: (String) -> Unit,
) {
    val hospital = account.hospital
    val board = account.board
    var month by rememberSaveable { mutableStateOf(YearMonth.now().toString()) }
    var selected by rememberSaveable { mutableStateOf<String?>(null) }
    val ym = YearMonth.parse(month)
    Text(hospital?.name ?: "Hospital", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
    if (hospital != null && hospital.verificationStatus != "verified") {
        Text("Verification is ${hospital.verificationStatus}.")
    }
    val pending = board.tokens.filter { it.status == "pending" }
    SectionCard("Approve coverage requests") {
        if (pending.isEmpty()) EmptyState("No pending requests.")
        pending.take(6).forEach { token -> TokenRow(token, onApprove, onDeny) }
        if (pending.size > 6) TextButton(onClick = { onOpen("approvals") }) { Text("Schedule admin") }
    }
    val openDays = board.shifts.map { utcDate(it.startEpochMillis) }.distinct().count { day ->
        board.shifts.filter { utcDate(it.startEpochMillis) == day }.any { shift ->
            board.assignments.none { it.shiftId == shift.id && it.status != "canceled" }
        }
    }
    Text("Pending approvals ${pending.size} · Open days $openDays")
    MonthCalendar(
        month = ym,
        dayColor = { date ->
            val key = date.toString()
            if (key in board.unavailableDays) return@MonthCalendar Danger
            val dayShifts = board.shifts.filter { utcDate(it.startEpochMillis) == key }
            if (dayShifts.isEmpty()) return@MonthCalendar null
            val filled = dayShifts.count { shift -> board.assignments.any { it.shiftId == shift.id && it.status != "canceled" } }
            when {
                filled == 0 -> Warning
                filled < dayShifts.size -> Accent
                else -> Success
            }
        },
        onDay = { selected = it.toString() },
        onPrev = { month = ym.minusMonths(1).toString() },
        onNext = { month = ym.plusMonths(1).toString() },
    )
    selected?.let { day ->
        SectionCard(day) {
            val blocked = day in board.unavailableDays
            OutlinedButton(onClick = { onUnavailable(day, !blocked) }) {
                Text(if (blocked) "Unblock day" else "Block day")
            }
            board.shifts.filter { utcDate(it.startEpochMillis) == day }.forEach { shift ->
                val holder = board.assignments.firstOrNull { it.shiftId == shift.id && it.status != "canceled" }
                Text("${shift.specialty} · ${money(shift.rateFloor)} · ${holder?.doctorName ?: "Open"}")
            }
            board.tokens.filter { it.shiftDate == day }.forEach { TokenRow(it, onApprove, onDeny) }
        }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        TextButton(onClick = { onOpen("approvals") }) { Text("Schedule admin") }
        TextButton(onClick = { onOpen("analytics") }) { Text("Analytics") }
        TextButton(onClick = { onOpen("billing") }) { Text("Billing") }
        TextButton(onClick = { onOpen("policy") }) { Text("Policy") }
    }
}

@Composable
private fun TokenRow(token: TokenRequest, onApprove: (TokenRequest) -> Unit, onDeny: (TokenRequest) -> Unit) {
    val name = token.doctorName.ifBlank { "Doctor" }
    val credential = token.credential.let { if (it.isBlank()) "" else ", $it" }
    Text("$name$credential · ${token.specialty} · ${token.shiftDate} · ${token.status}")
    if (token.status == "pending") {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = { onApprove(token) }) { Text("Approve") }
            OutlinedButton(onClick = { onDeny(token) }) { Text("Deny") }
        }
    }
}

@Composable
private fun Approvals(account: AccountState, onApprove: (TokenRequest) -> Unit, onDeny: (TokenRequest) -> Unit, onClose: () -> Unit) {
    var filter by rememberSaveable { mutableStateOf("pending") }
    var query by rememberSaveable { mutableStateOf("") }
    Text("Schedule admin", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        listOf("pending", "approved", "denied").forEach { status ->
            FilterChip(selected = filter == status, onClick = { filter = status }, label = { Text(status) })
        }
    }
    OutlinedTextField(query, { query = it }, label = { Text("Search doctor or specialty") }, modifier = Modifier.fillMaxWidth())
    val rows = account.board.tokens.filter {
        (filter == "approved" && (it.status == "approved" || it.status == "auto_approved") || it.status == filter) &&
            (query.isBlank() || it.doctorName.contains(query, true) || it.specialty.contains(query, true))
    }
    if (rows.isEmpty()) EmptyState("No ${filter} requests.")
    rows.forEach { token ->
        SectionCard(token.shiftDate) { TokenRow(token, onApprove, onDeny) }
    }
    TextButton(onClick = onClose) { Text("Close") }
}

@Composable
private fun AlterShifts(account: AccountState, onPost: (String, Long, Double, Boolean) -> Unit, onSavePolicy: (SchedulingPolicy) -> Unit) {
    var specialty by rememberSaveable { mutableStateOf(SPECIALTIES.first()) }
    var rate by rememberSaveable { mutableStateOf(account.board.policy.rateFor(specialty).toString()) }
    var algorithm by rememberSaveable { mutableStateOf(true) }
    var day by rememberSaveable { mutableStateOf(LocalDate.now().plusDays(1).toString()) }
    Text("Alter shifts", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
    Text("Day rates")
    SPECIALTIES.take(8).chunked(2).forEach { row ->
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            row.forEach { name ->
                FilterChip(selected = specialty == name, onClick = {
                    specialty = name
                    rate = account.board.policy.rateFor(name).toString()
                }, label = { Text(name) })
            }
        }
    }
    OutlinedTextField(day, { day = it }, label = { Text("Date YYYY-MM-DD") }, modifier = Modifier.fillMaxWidth())
    OutlinedTextField(rate, { rate = it }, label = { Text("Rate floor") }, modifier = Modifier.fillMaxWidth())
    FilterChip(selected = algorithm, onClick = { algorithm = !algorithm }, label = { Text(if (algorithm) "Smart algo" else "Locked rate") })
    PrimaryButton("Post shift") {
        val parsed = runCatching { LocalDate.parse(day) }.getOrNull() ?: return@PrimaryButton
        val amount = rate.toDoubleOrNull() ?: return@PrimaryButton
        val epoch = parsed.atStartOfDay(java.time.ZoneOffset.UTC).toInstant().toEpochMilli()
        onPost(specialty, epoch, amount, algorithm)
    }
    Text("Specialty base rates")
    var draft by rememberSaveable(specialty) {
        mutableStateOf(account.board.policy.rateFor(specialty).toString())
    }
    OutlinedTextField(draft, { draft = it }, label = { Text("$specialty base") }, modifier = Modifier.fillMaxWidth())
    OutlinedButton(onClick = {
        val amount = draft.toDoubleOrNull() ?: return@OutlinedButton
        onSavePolicy(account.board.policy.copy(specialtyBaseRates = account.board.policy.specialtyBaseRates + (specialty to amount)))
    }) { Text("Save specialty rate") }
}

@Composable
private fun DoctorsTab(account: AccountState, onAutoApprove: (RosterDoctor, Boolean) -> Unit, onTokenLimit: (String, Int) -> Unit) {
    var specialty by rememberSaveable { mutableStateOf("All") }
    Text("Roster", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
    FilterChip(selected = specialty == "All", onClick = { specialty = "All" }, label = { Text("All") })
    val doctors = account.board.roster.filter { specialty == "All" || specialty in it.specialties }
    if (doctors.isEmpty()) EmptyState("No doctors on the roster yet. Approving a request adds them.")
    doctors.forEach { doctor ->
        SectionCard(doctor.displayName) {
            Text(doctor.specialties.joinToString().ifBlank { "Specialty on file" })
            Text("Verification ${doctor.verificationStatus}")
            val upcoming = account.board.assignments.count { it.doctorId == doctor.doctorId && it.status != "canceled" }
            Text("Upcoming shifts $upcoming")
            FilterChip(
                selected = doctor.autoApprove,
                onClick = { onAutoApprove(doctor, !doctor.autoApprove) },
                label = { Text(if (doctor.autoApprove) "Auto-approve on" else "Auto-approve off") },
            )
            val limit = account.board.policy.dailyTokens(doctor.doctorId)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Daily tokens $limit")
                OutlinedButton(onClick = { onTokenLimit(doctor.doctorId, (limit - 1).coerceAtLeast(0)) }) { Text("−") }
                OutlinedButton(onClick = { onTokenLimit(doctor.doctorId, (limit + 1).coerceAtMost(20)) }) { Text("+") }
            }
        }
    }
}

@Composable
private fun PolicyEditor(policy: SchedulingPolicy, onSave: (SchedulingPolicy) -> Unit, onClose: () -> Unit) {
    var approve by rememberSaveable { mutableStateOf(policy.administratorApproveShifts) }
    var cancelWindow by rememberSaveable { mutableStateOf(policy.cancelWindowHours.toString()) }
    var tradeWindow by rememberSaveable { mutableStateOf(policy.tradeWindowHours.toString()) }
    var base by rememberSaveable { mutableStateOf(policy.basePenaltyAmount.toString()) }
    var tradeFee by rememberSaveable { mutableStateOf(policy.tradePenaltyAmount.toString()) }
    var tradeOn by rememberSaveable { mutableStateOf(policy.tradePenaltiesEnabled) }
    var tokens by rememberSaveable { mutableStateOf(policy.defaultDailyTokens.toString()) }
    Text("Scheduling policy", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
    FilterChip(selected = approve, onClick = { approve = !approve }, label = { Text(if (approve) "Administrator approves" else "Auto for verified doctors") })
    OutlinedTextField(cancelWindow, { cancelWindow = it }, label = { Text("Cancel window hours") }, modifier = Modifier.fillMaxWidth())
    OutlinedTextField(tradeWindow, { tradeWindow = it }, label = { Text("Trade window hours") }, modifier = Modifier.fillMaxWidth())
    OutlinedTextField(base, { base = it }, label = { Text("Base cancel penalty") }, modifier = Modifier.fillMaxWidth())
    FilterChip(selected = tradeOn, onClick = { tradeOn = !tradeOn }, label = { Text("Trade penalties") })
    OutlinedTextField(tradeFee, { tradeFee = it }, label = { Text("Trade penalty amount") }, modifier = Modifier.fillMaxWidth())
    OutlinedTextField(tokens, { tokens = it }, label = { Text("Default daily tokens") }, modifier = Modifier.fillMaxWidth())
    Text("Cancel scale: ${policy.cancellationPenaltyScale.joinToString { "${it.hoursBeforeStart}h → ${it.penaltyPercent}%" }}")
    PrimaryButton("Save policy") {
        onSave(
            policy.copy(
                administratorApproveShifts = approve,
                cancelWindowHours = cancelWindow.toIntOrNull() ?: policy.cancelWindowHours,
                tradeWindowHours = tradeWindow.toIntOrNull() ?: policy.tradeWindowHours,
                basePenaltyAmount = base.toDoubleOrNull() ?: policy.basePenaltyAmount,
                tradePenaltiesEnabled = tradeOn,
                tradePenaltyAmount = tradeFee.toDoubleOrNull() ?: policy.tradePenaltyAmount,
                defaultDailyTokens = (tokens.toIntOrNull() ?: policy.defaultDailyTokens).coerceIn(0, 20),
            ),
        )
    }
    TextButton(onClick = onClose) { Text("Close") }
}

@Composable
private fun Analytics(account: AccountState, onClose: () -> Unit) {
    val board = account.board
    val filled = board.assignments.count { it.status != "canceled" }
    val canceled = board.assignments.count { it.status == "canceled" } + board.penalties.count { it.type == "cancel" }
    val trades = board.trades.count { it.state == "accepted" }
    Text("Analytics", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
    SectionCard("Coverage") {
        Text("Filled assignments $filled")
        Text("Cancellations $canceled")
        Text("Accepted trades $trades")
        val window = board.shifts.size.coerceAtLeast(1)
        Text("Posted shifts in window ${board.shifts.size}. Fill snapshot ${filled * 100 / window}%.")
    }
    SectionCard("Verified savings") {
        if (board.savings.isEmpty()) {
            EmptyState("No verified savings yet. Savings appear when a shift is filled before the rate escalates.")
        } else {
            Text(money(board.savings.sumOf { it.amount }))
            board.savings.take(8).forEach { event ->
                Text("${event.kind} · ${event.specialty} · ${money(event.amount)}")
            }
        }
    }
    TextButton(onClick = onClose) { Text("Close") }
}

@Composable
private fun Billing(account: AccountState, onClose: () -> Unit) {
    Text("Billing", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
    val lines = account.board.assignments.filter { it.status != "canceled" }.mapNotNull { row ->
        account.board.shifts.firstOrNull { it.id == row.shiftId }?.let { shift ->
            utcDate(shift.startEpochMillis).take(7) to shift.rateFloor
        }
    }
    if (lines.isEmpty()) {
        EmptyState("No committed payouts yet. Real assignments show up here after doctors are scheduled.")
    } else {
        lines.groupBy({ it.first }, { it.second }).toSortedMap().forEach { (month, amounts) ->
            SectionCard(month) {
                Text("${amounts.size} shifts · ${money(amounts.sum())}")
            }
        }
    }
    TextButton(onClick = onClose) { Text("Close") }
}

@Composable
private fun HospitalSettings(
    account: AccountState,
    onSignOut: () -> Unit,
    onAppearance: (String) -> Unit,
    onPriority: (Boolean) -> Unit,
    onAutoPay: (Boolean) -> Unit,
    onPrivacy: () -> Unit,
    onSupport: () -> Unit,
    onOpen: (String) -> Unit,
    onClose: () -> Unit,
) {
    SectionCard("Settings") {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("System", "Light", "Dark").forEach { mode ->
                FilterChip(selected = account.appearance == mode, onClick = { onAppearance(mode) }, label = { Text(mode) })
            }
        }
        TextButton(onClick = { onOpen("policy") }) { Text("Scheduling policy") }
        TextButton(onClick = { onOpen("analytics") }) { Text("Analytics") }
        TextButton(onClick = { onOpen("billing") }) { Text("Billing") }
        TextButton(onClick = { onOpen("approvals") }) { Text("Schedule admin") }
        FilterChip(account.priorityPosting, { onPriority(!account.priorityPosting) }, label = { Text("Priority posting") })
        FilterChip(account.autoPayInvoices, { onAutoPay(!account.autoPayInvoices) }, label = { Text("Auto-pay invoices") })
        TextButton(onClick = onPrivacy) { Text("Privacy Policy") }
        TextButton(onClick = onSupport) { Text("Support") }
        Text("To delete your account, contact support from the privacy policy. Deletion is not done inside the app.")
        OutlinedButton(onClick = onSignOut, modifier = Modifier.fillMaxWidth()) { Text("Sign out") }
        TextButton(onClick = onClose) { Text("Close") }
    }
}
