// @ts-check
// =============================================================================
// GitSync.js
//
// Core utilities for parsing git snapshots, formatting device-tagged commits,
// and handling multi-device sync metadata for tablerase.ardoise.
// =============================================================================

/**
 * @typedef {Object} GitSnapshot
 * @property {string} hash - Full commit hash
 * @property {string} shortHash - 7-char short hash
 * @property {string} author - Commit author name
 * @property {string} email - Commit author email
 * @property {number} timestamp - Epoch timestamp in milliseconds
 * @property {string} message - Full commit message
 * @property {string} cleanMessage - Commit message without device prefix
 * @property {string} deviceName - Identified device name
 * @property {number} [pendingCount] - Number of pending tasks if recorded in commit message
 */

/**
 * Extracts a device name from a commit message prefix "[DeviceName] ..." or author name.
 * @param {string} message
 * @param {string} [fallbackAuthor]
 * @returns {string}
 */
function extractDeviceName(message, fallbackAuthor) {
  if (!message) return fallbackAuthor || "unknown"
  var match = String(message).trim().match(/^\[([^\]]+)\]/)
  if (match && match[1]) {
    return match[1].trim()
  }
  return fallbackAuthor ? String(fallbackAuthor).trim() : "unknown"
}

/**
 * Extracts clean message without "[DeviceName]" prefix.
 * @param {string} message
 * @returns {string}
 */
function extractCleanMessage(message) {
  if (!message) return ""
  return String(message).replace(/^\[[^\]]+\]\s*/, "").trim()
}

/**
 * Extracts pending count from commit message if present (e.g. "(14 pending)").
 * @param {string} message
 * @returns {number|undefined}
 */
function extractPendingCount(message) {
  if (!message) return undefined
  var match = String(message).match(/\((\d+)\s+pending\)/)
  if (match && match[1]) {
    var num = parseInt(match[1], 10)
    return isNaN(num) ? undefined : num
  }
  return undefined
}

/**
 * Parses raw git log output into structured snapshot objects.
 * Format expected: %H|%an|%ae|%at|%s
 * @param {string} rawLog
 * @returns {GitSnapshot[]}
 */
function parseGitLog(rawLog) {
  if (!rawLog || typeof rawLog !== "string") return []
  var lines = rawLog.split("\n")
  var snapshots = []

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var parts = line.split("|")
    if (parts.length < 5) continue

    var hash = parts[0].trim()
    var author = parts[1].trim()
    var email = parts[2].trim()
    var epochSec = parseInt(parts[3].trim(), 10)
    var timestamp = !isNaN(epochSec) ? epochSec * 1000 : Date.now()
    var message = parts.slice(4).join("|").trim()

    var deviceName = extractDeviceName(message, author)
    var cleanMessage = extractCleanMessage(message)
    var pendingCount = extractPendingCount(message)

    snapshots.push({
      hash: hash,
      shortHash: hash.substring(0, 7),
      author: author,
      email: email,
      timestamp: timestamp,
      message: message,
      cleanMessage: cleanMessage,
      deviceName: deviceName,
      pendingCount: pendingCount
    })
  }

  return snapshots
}

/**
 * Builds a standardized device-tagged commit message.
 * @param {string} deviceName
 * @param {string} action
 * @param {number} [pendingCount]
 * @returns {string}
 */
function buildCommitMessage(deviceName, action, pendingCount) {
  var dev = (deviceName && String(deviceName).trim()) ? String(deviceName).trim() : "unknown"
  var act = (action && String(action).trim()) ? String(action).trim() : "Update tasks"
  if (pendingCount !== undefined && pendingCount !== null && !isNaN(pendingCount)) {
    return "[" + dev + "] " + act + " (" + pendingCount + " pending)"
  }
  return "[" + dev + "] " + act
}

/**
 * Formats a relative timestamp (e.g. "just now", "5m ago", "2h ago", "yesterday", "Sep 28").
 * @param {number} timestampMs
 * @param {number} [nowMs]
 * @returns {string}
 */
function formatRelativeTime(timestampMs, nowMs) {
  var now = nowMs !== undefined ? nowMs : Date.now()
  var diffSec = Math.floor((now - timestampMs) / 1000)

  if (diffSec < 60) return "just now"
  var diffMin = Math.floor(diffSec / 60)
  if (diffMin < 60) return diffMin + "m ago"
  var diffHours = Math.floor(diffMin / 60)
  if (diffHours < 24) return diffHours + "h ago"
  var diffDays = Math.floor(diffHours / 24)
  if (diffDays === 1) return "yesterday"
  if (diffDays < 7) return diffDays + "d ago"

  var d = new Date(timestampMs)
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  return months[d.getMonth()] + " " + d.getDate()
}

/**
 * Validates a git remote URL (SSH or HTTPS).
 * @param {string} url
 * @returns {boolean}
 */
function isValidRemoteUrl(url) {
  if (!url || typeof url !== "string") return false
  var s = url.trim()
  if (!s) return false
  // git@github.com:user/repo.git or https://github.com/user/repo.git or ssh://...
  var sshRegex = /^(git@[a-zA-Z0-9_\-\.]+:|ssh:\/\/[a-zA-Z0-9_\-\.@:]+\/)[a-zA-Z0-9_\-\.\/]+(?:\.git)?$/
  var httpsRegex = /^https?:\/\/[a-zA-Z0-9_\-\.]+(?::[0-9]+)?\/[a-zA-Z0-9_\-\.\/]+(?:\.git)?$/
  return sshRegex.test(s) || httpsRegex.test(s)
}

/**
 * Filters an array of GitSnapshot objects by a free-text query.
 *
 * Splits the query into whitespace-separated tokens. A snapshot matches only
 * when **every** token is found in at least one of the following fields
 * (all comparisons are case-insensitive):
 *  - `cleanMessage` / `message`
 *  - `deviceName` (strips a leading `#` or surrounding `[…]` from the token
 *    before comparing so `#laptop` and `[laptop]` both find device "laptop")
 *  - `shortHash` / `hash` (substring match)
 *  - `author`
 *
 * Returns the original array unchanged when the query is empty or whitespace.
 * Returns `[]` safely when the input is not a valid array.
 *
 * @param {GitSnapshot[]} snapshots
 * @param {string} query
 * @returns {GitSnapshot[]}
 */
function filterSnapshots(snapshots, query) {
  if (!Array.isArray(snapshots)) return []
  if (!query || typeof query !== "string" || !query.trim()) return snapshots

  var tokens = query.trim().toLowerCase().split(/\s+/).filter(Boolean)
  if (tokens.length === 0) return snapshots

  return snapshots.filter(function(snap) {
    return tokens.every(function(token) {
      // Normalize device-tag syntax: strip leading # or surrounding [...]
      var deviceToken = token.replace(/^\[(.+)\]$/, "$1").replace(/^#/, "")

      var msg = (snap.cleanMessage || snap.message || "").toLowerCase()
      var device = (snap.deviceName || "").toLowerCase()
      var shortH = (snap.shortHash || "").toLowerCase()
      var fullH = (snap.hash || "").toLowerCase()
      var auth = (snap.author || "").toLowerCase()

      return (
        msg.indexOf(token) !== -1 ||
        device.indexOf(deviceToken) !== -1 ||
        shortH.indexOf(token) !== -1 ||
        fullH.indexOf(token) !== -1 ||
        auth.indexOf(token) !== -1
      )
    })
  })
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    extractDeviceName,
    extractCleanMessage,
    extractPendingCount,
    parseGitLog,
    buildCommitMessage,
    formatRelativeTime,
    isValidRemoteUrl,
    filterSnapshots
  }
}
