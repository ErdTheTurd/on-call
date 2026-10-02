package com.eporthospine.mdshift.data

import com.eporthospine.mdshift.domain.UserRole
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.request.header
import io.ktor.client.request.request
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64

interface SupabaseApi {
    suspend fun signUp(email: String, password: String, role: UserRole): AuthPayload
    suspend fun verifyOtp(email: String, token: String, type: String, accessToken: String?): AuthPayload
    suspend fun passwordGrant(email: String, password: String): AuthPayload
    suspend fun refresh(refreshToken: String): AuthPayload
    suspend fun resendSignup(email: String)
    suspend fun updateUserEmail(accessToken: String, email: String)
    suspend fun currentUser(accessToken: String): String
    suspend fun enrollTotp(accessToken: String): TotpEnrollment
    suspend fun challengeTotp(accessToken: String, factorId: String): String
    suspend fun verifyTotp(accessToken: String, factorId: String, challengeId: String, code: String): AuthPayload
    suspend fun exchangePkce(code: String, verifier: String): AuthPayload
    suspend fun exchangeIdToken(provider: String, idToken: String): AuthPayload
    suspend fun logout(accessToken: String, refreshToken: String?)
    suspend fun restGet(path: String, accessToken: String): String
    suspend fun restSend(path: String, method: String, body: String?, accessToken: String, prefer: String?): String
    suspend fun invoke(name: String, body: String, accessToken: String): String
    suspend fun getPublic(url: String): String
    fun authorizeUrl(provider: String, redirectTo: String, codeChallenge: String): String
}

object Pkce {
    private val alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"

    fun verifier(): String {
        val random = SecureRandom()
        return buildString(64) { repeat(64) { append(alphabet[random.nextInt(alphabet.length)]) } }
    }

    fun challenge(verifier: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray(Charsets.US_ASCII))
        return Base64.getUrlEncoder().withoutPadding().encodeToString(digest)
    }
}

class KtorSupabaseApi(
    private val http: HttpClient,
    private val baseUrl: String,
    private val anonKey: String,
) : SupabaseApi {
    override suspend fun signUp(email: String, password: String, role: UserRole): AuthPayload =
        parseAuthPayload(
            post(
                "auth/v1/signup",
                buildJsonObject {
                    put("email", email)
                    put("password", password)
                    put("data", buildJsonObject { put("role", role.wire) })
                    put("gotrue_meta_security", JsonObject(emptyMap()))
                }.toString(),
            ),
        )

    override suspend fun verifyOtp(email: String, token: String, type: String, accessToken: String?): AuthPayload =
        parseAuthPayload(
            post(
                "auth/v1/verify",
                buildJsonObject {
                    put("email", email)
                    put("token", token)
                    put("type", type)
                }.toString(),
                accessToken,
            ),
        )

    override suspend fun passwordGrant(email: String, password: String): AuthPayload =
        parseAuthPayload(
            post(
                "auth/v1/token?grant_type=password",
                buildJsonObject {
                    put("email", email)
                    put("password", password)
                }.toString(),
            ),
        )

    override suspend fun refresh(refreshToken: String): AuthPayload =
        parseAuthPayload(
            post(
                "auth/v1/token?grant_type=refresh_token",
                buildJsonObject { put("refresh_token", refreshToken) }.toString(),
            ),
        )

    override suspend fun resendSignup(email: String) {
        post("auth/v1/resend", buildJsonObject { put("email", email); put("type", "signup") }.toString())
    }

    override suspend fun updateUserEmail(accessToken: String, email: String) {
        send("auth/v1/user", HttpMethod.Put, buildJsonObject { put("email", email) }.toString(), accessToken, null)
    }

    override suspend fun currentUser(accessToken: String): String =
        send("auth/v1/user", HttpMethod.Get, null, accessToken, null)

    override suspend fun enrollTotp(accessToken: String): TotpEnrollment {
        val body = send(
            "auth/v1/factors",
            HttpMethod.Post,
            buildJsonObject {
                put("factor_type", "totp")
                put("friendly_name", "MD Shift")
            }.toString(),
            accessToken,
            null,
        )
        val json = AppJson.parseToJsonElement(body).jsonObject
        val totp = json["totp"]?.jsonObject
        val secret = totp?.text("secret") ?: throw ApiException("Unexpected response from the server.")
        val id = json.text("id") ?: throw ApiException("Unexpected response from the server.")
        return TotpEnrollment(id, secret)
    }

    override suspend fun challengeTotp(accessToken: String, factorId: String): String {
        val body = send("auth/v1/factors/$factorId/challenge", HttpMethod.Post, "{}", accessToken, null)
        return AppJson.parseToJsonElement(body).jsonObject.text("id")
            ?: throw ApiException("Unexpected response from the server.")
    }

    override suspend fun verifyTotp(
        accessToken: String,
        factorId: String,
        challengeId: String,
        code: String,
    ): AuthPayload = parseAuthPayload(
        send(
            "auth/v1/factors/$factorId/verify",
            HttpMethod.Post,
            buildJsonObject {
                put("challenge_id", challengeId)
                put("code", code)
            }.toString(),
            accessToken,
            null,
        ),
    )

    override suspend fun exchangePkce(code: String, verifier: String): AuthPayload =
        parseAuthPayload(
            post(
                "auth/v1/token?grant_type=pkce",
                buildJsonObject {
                    put("auth_code", code)
                    put("code_verifier", verifier)
                }.toString(),
            ),
        )

    override suspend fun exchangeIdToken(provider: String, idToken: String): AuthPayload =
        parseAuthPayload(
            post(
                "auth/v1/token?grant_type=id_token",
                buildJsonObject {
                    put("provider", provider)
                    put("id_token", idToken)
                }.toString(),
            ),
        )

    override suspend fun logout(accessToken: String, refreshToken: String?) {
        runCatching {
            send(
                "auth/v1/logout",
                HttpMethod.Post,
                buildJsonObject {
                    if (refreshToken != null) put("refresh_token", refreshToken)
                }.toString(),
                accessToken,
                null,
            )
        }
    }

    override suspend fun restGet(path: String, accessToken: String): String =
        send(path, HttpMethod.Get, null, accessToken, null)

    override suspend fun restSend(path: String, method: String, body: String?, accessToken: String, prefer: String?): String =
        send(path, HttpMethod.parse(method), body, accessToken, prefer)

    override suspend fun invoke(name: String, body: String, accessToken: String): String =
        send("functions/v1/$name", HttpMethod.Post, body, accessToken, null)

    override suspend fun getPublic(url: String): String {
        val response = http.request(url) { method = HttpMethod.Get }
        val text = response.bodyAsText()
        if (response.status.value !in 200..299) throw ApiException(humanizeError(response.status.value, text), response.status.value)
        return text
    }

    override fun authorizeUrl(provider: String, redirectTo: String, codeChallenge: String): String {
        val root = baseUrl.trimEnd('/')
        val redirect = java.net.URLEncoder.encode(redirectTo, Charsets.UTF_8.name())
        return "$root/auth/v1/authorize?provider=$provider&redirect_to=$redirect&code_challenge=$codeChallenge&code_challenge_method=S256"
    }

    private suspend fun post(path: String, body: String, accessToken: String? = null): String =
        send(path, HttpMethod.Post, body, accessToken, null)

    private suspend fun send(
        path: String,
        method: HttpMethod,
        body: String?,
        accessToken: String?,
        prefer: String?,
    ): String {
        val root = baseUrl.trimEnd('/')
        val url = if (path.startsWith("http")) path else "$root/$path"
        val response = http.request(url) {
            this.method = method
            header("apikey", anonKey)
            header("Content-Type", "application/json")
            header("Authorization", "Bearer ${accessToken ?: anonKey}")
            if (prefer != null) header("Prefer", prefer)
            if (body != null && method != HttpMethod.Get) setBody(body)
        }
        val text = response.bodyAsText()
        if (response.status == HttpStatusCode.NoContent) return ""
        if (response.status.value !in 200..299) {
            throw ApiException(humanizeError(response.status.value, text), response.status.value)
        }
        return text
    }

    companion object {
        fun create(baseUrl: String, anonKey: String): KtorSupabaseApi =
            KtorSupabaseApi(
                http = HttpClient(OkHttp) {
                    expectSuccess = false
                },
                baseUrl = baseUrl,
                anonKey = anonKey,
            )
    }
}
