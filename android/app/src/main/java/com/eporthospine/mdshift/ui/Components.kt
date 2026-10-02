package com.eporthospine.mdshift.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.TextStyle
import java.util.Locale

fun monthCells(month: YearMonth): List<LocalDate?> {
    val first = month.atDay(1)
    val pad = first.dayOfWeek.value % 7
    val cells = MutableList<LocalDate?>(pad) { null }
    for (day in 1..month.lengthOfMonth()) cells += month.atDay(day)
    while (cells.size % 7 != 0) cells += null
    return cells
}

@Composable
fun MonthCalendar(
    month: YearMonth,
    dayColor: (LocalDate) -> androidx.compose.ui.graphics.Color?,
    onDay: (LocalDate) -> Unit,
    onPrev: () -> Unit,
    onNext: () -> Unit,
) {
    Column(Modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            OutlinedButton(onClick = onPrev) { Text("Prev") }
            Text(
                "${month.month.getDisplayName(TextStyle.FULL, Locale.US)} ${month.year}",
                modifier = Modifier.weight(1f).padding(horizontal = 8.dp),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            OutlinedButton(onClick = onNext) { Text("Next") }
        }
        Spacer(Modifier.height(8.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            listOf("S", "M", "T", "W", "T", "F", "S").forEach {
                Text(it, modifier = Modifier.weight(1f), color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            }
        }
        monthCells(month).chunked(7).forEach { week ->
            Row(Modifier.fillMaxWidth().padding(vertical = 2.dp)) {
                week.forEach { date ->
                    val tint = date?.let(dayColor)
                    Box(
                        Modifier
                            .weight(1f)
                            .height(40.dp)
                            .padding(2.dp)
                            .clip(CircleShape)
                            .background(tint ?: androidx.compose.ui.graphics.Color.Transparent)
                            .then(
                                if (date != null) {
                                    Modifier
                                        .semantics { contentDescription = date.toString() }
                                        .clickable { onDay(date) }
                                } else {
                                    Modifier
                                },
                            ),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (date != null) {
                            Text(
                                date.dayOfMonth.toString(),
                                color = if (tint != null) androidx.compose.ui.graphics.Color.White else MaterialTheme.colorScheme.onSurface,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun SectionCard(title: String, body: @Composable () -> Unit) {
    Card(Modifier.fillMaxWidth().padding(vertical = 6.dp), shape = RoundedCornerShape(18.dp)) {
        Column(Modifier.padding(16.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(8.dp))
            body()
        }
    }
}

@Composable
fun PrimaryButton(text: String, enabled: Boolean = true, onClick: () -> Unit) {
    Button(onClick = onClick, enabled = enabled, modifier = Modifier.fillMaxWidth().height(48.dp)) {
        Text(text)
    }
}

@Composable
fun SampleBanner() {
    Text(
        "Sample data — not a live hospital record",
        modifier = Modifier
            .fillMaxWidth()
            .background(Warning.copy(alpha = 0.15f), RoundedCornerShape(12.dp))
            .padding(10.dp),
        color = Warning,
        fontWeight = FontWeight.SemiBold,
    )
}

@Composable
fun SyncBanner(message: String, onRetry: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface, RoundedCornerShape(14.dp))
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text("Saved on this device only", fontWeight = FontWeight.SemiBold)
            Text(message.ifBlank { "We can't reach the server right now." }, style = MaterialTheme.typography.bodySmall)
        }
        OutlinedButton(onClick = onRetry) { Text("Retry") }
    }
}

@Composable
fun EmptyState(text: String) {
    Text(text, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f), modifier = Modifier.padding(vertical = 8.dp))
}

@Composable
fun StatusDot(color: androidx.compose.ui.graphics.Color, label: String) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(end = 10.dp)) {
        Box(Modifier.size(10.dp).clip(CircleShape).background(color).semantics { contentDescription = label })
        Text(label, modifier = Modifier.padding(start = 4.dp), style = MaterialTheme.typography.labelMedium)
    }
}
