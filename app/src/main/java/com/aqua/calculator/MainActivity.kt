package com.aqua.calculator

import android.app.Activity
import android.os.Bundle
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import java.math.BigDecimal
import java.math.RoundingMode

class MainActivity : Activity() {
    private lateinit var display: TextView
    private lateinit var history: TextView
    private var expression = ""
    private var justCalculated = false
    private var themeIndex = 0

    private data class Palette(val background: Int, val panel: Int, val text: Int, val accent: Int, val key: Int)
    private val palettes = listOf(
        Palette(Color.rgb(8, 25, 48), Color.rgb(18, 48, 75), Color.WHITE, Color.rgb(55, 210, 205), Color.rgb(30, 68, 95)),
        Palette(Color.rgb(245, 248, 255), Color.WHITE, Color.rgb(25, 39, 65), Color.rgb(65, 110, 230), Color.rgb(230, 237, 249)),
        Palette(Color.rgb(34, 20, 49), Color.rgb(59, 37, 78), Color.WHITE, Color.rgb(213, 130, 255), Color.rgb(82, 55, 103)),
        Palette(Color.rgb(20, 39, 31), Color.rgb(34, 64, 49), Color.WHITE, Color.rgb(126, 220, 155), Color.rgb(48, 83, 63))
    )
    private val palette get() = palettes[themeIndex]

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        buildUi()
    }

    private fun rounded(color: Int, radius: Float = 28f): GradientDrawable =
        GradientDrawable().apply { setColor(color); cornerRadius = radius }

    private fun buildUi() {
        val p = palette
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(22, 26, 22, 22)
            setBackgroundColor(p.background)
        }

        val top = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val title = TextView(this).apply {
            text = "AQUA"; textSize = 17f; setTextColor(p.text)
            typeface = Typeface.DEFAULT_BOLD; letterSpacing = 0.18f
        }
        val theme = Button(this).apply {
            text = "THEME"; textSize = 11f; isAllCaps = false
            setTextColor(p.text); background = rounded(p.panel, 40f)
            setOnClickListener { themeIndex = (themeIndex + 1) % palettes.size; buildUi() }
        }
        top.addView(title, LinearLayout.LayoutParams(0, 52, 1f))
        top.addView(theme, LinearLayout.LayoutParams(104, 48))
        root.addView(top)

        history = TextView(this).apply {
            text = "Your calculations"; textSize = 13f
            setTextColor(p.text); alpha = 0.58f; gravity = Gravity.END or Gravity.CENTER_VERTICAL
        }
        root.addView(history, LinearLayout.LayoutParams(-1, 42))

        display = TextView(this).apply {
            text = "0"; textSize = 48f; setTextColor(p.text)
            gravity = Gravity.END or Gravity.CENTER_VERTICAL
            typeface = Typeface.create("sans-serif-light", Typeface.NORMAL)
            maxLines = 1
        }
        root.addView(display, LinearLayout.LayoutParams(-1, 0, 1.1f))

        val keys = listOf(
            listOf("AC", "⌫", "%", "÷"),
            listOf("7", "8", "9", "×"),
            listOf("4", "5", "6", "−"),
            listOf("1", "2", "3", "+"),
            listOf("±", "0", ".", "=")
        )
        val grid = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        keys.forEach { rowKeys ->
            val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
            rowKeys.forEach { label ->
                val isOperator = label in listOf("÷", "×", "−", "+", "=")
                val isUtility = label in listOf("AC", "⌫", "%", "±")
                val button = Button(this).apply {
                    text = label
                    textSize = if (label.length > 1) 17f else 23f
                    isAllCaps = false
                    setTextColor(if (isOperator) p.background else p.text)
                    background = rounded(if (isOperator) p.accent else if (isUtility) p.panel else p.key, 30f)
                    setOnClickListener { onKey(label) }
                    stateListAnimator = null
                }
                val lp = LinearLayout.LayoutParams(0, 70, 1f).apply { setMargins(5, 5, 5, 5) }
                row.addView(button, lp)
            }
            grid.addView(row)
        }
        root.addView(grid, LinearLayout.LayoutParams(-1, 0, 2.2f))
        val footer = TextView(this).apply {
            text = "A simple space for everyday maths"
            textSize = 11f; gravity = Gravity.CENTER
            setTextColor(p.text); alpha = 0.5f
        }
        root.addView(footer, LinearLayout.LayoutParams(-1, 34))
        setContentView(root)
        updateDisplay()
    }

    private fun onKey(key: String) {
        when (key) {
            "AC" -> { expression = ""; history.text = "Your calculations"; justCalculated = false }
            "⌫" -> { expression = expression.dropLast(1); justCalculated = false }
            "=" -> calculate()
            "±" -> {
                val value = expression.toDoubleOrNull()
                if (value != null) expression = format(-value)
            }
            "%" -> {
                val value = expression.toDoubleOrNull()
                if (value != null) expression = format(value / 100.0)
            }
            else -> {
                if (justCalculated && key.firstOrNull()?.isDigit() == true) expression = ""
                justCalculated = false
                if (key in listOf("+", "−", "×", "÷")) {
                    if (expression.isNotEmpty() && expression.last() in "+−×÷") expression = expression.dropLast(1)
                    if (expression.isNotEmpty()) expression += key
                } else if (key == ".") {
                    val current = expression.substring(expression.indexOfLast { it in "+−×÷" } + 1)
                    if (!current.contains(".")) expression += if (current.length == 0) "0." else "."
                } else expression += key
            }
        }
        updateDisplay()
    }

    private fun calculate() {
        try {
            val result = evaluate(expression)
            history.text = "$expression ="
            expression = format(result)
            justCalculated = true
        } catch (_: Exception) {
            display.text = "Error"
        }
    }

    private fun evaluate(input: String): Double {
        val tokens = Regex("(?<=[+−×÷])|(?=[+−×÷])").split(input).filter { it.isNotBlank() }
        if (tokens.isEmpty()) return 0.0
        var result = tokens[0].toDouble()
        var i = 1
        while (i + 1 < tokens.size) {
            val op = tokens[i]
            val n = tokens[i + 1].toDouble()
            result = when (op) {
                "+" -> result + n
                "−" -> result - n
                "×" -> result * n
                "÷" -> { if (n == 0.0) throw ArithmeticException(); result / n }
                else -> result
            }
            i += 2
        }
        return result
    }

    private fun format(value: Double): String {
        if (!value.isFinite()) return "Error"
        return BigDecimal.valueOf(value).setScale(8, RoundingMode.HALF_UP)
            .stripTrailingZeros().toPlainString()
    }

    private fun updateDisplay() {
        if (::display.isInitialized) display.text = if (expression.isEmpty()) "0" else expression
    }
}
