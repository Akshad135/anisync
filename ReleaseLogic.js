// ReleaseLogic.js - Pure JavaScript business logic for AniSync plugin
// Handles AniList GraphQL queries, MAL list parsing, countdowns, and notifications.

var ANILIST_ENDPOINT = "https://graphql.anilist.co"

// ----------------------------------------------------------- AniList Queries

function buildAniListUserQuery(username) {
  var query = [
    "query ($userName: String) {",
    "  user: User(name: $userName) {",
    "    id",
    "    name",
    "    bannerImage",
    "    avatar {",
    "      medium",
    "      large",
    "    }",
    "  }",
    "  anime: MediaListCollection(userName: $userName, type: ANIME, status: CURRENT) {",
    "    lists {",
    "      name",
    "      status",
    "      entries {",
    "        id",
    "        progress",
    "        score",
    "        media {",
    "          id",
    "          title {",
    "            romaji",
    "            english",
    "            native",
    "          }",
    "          status",
    "          format",
    "          episodes",
    "          nextAiringEpisode {",
    "            id",
    "            episode",
    "            airingAt",
    "            timeUntilAiring",
    "          }",
    "          coverImage {",
    "            medium",
    "            large",
    "          }",
    "          bannerImage",
    "          siteUrl",
    "          genres",
    "          averageScore",
    "        }",
    "      }",
    "    }",
    "  }",
    "  manga: MediaListCollection(userName: $userName, type: MANGA, status: CURRENT) {",
    "    lists {",
    "      name",
    "      status",
    "      entries {",
    "        id",
    "        progress",
    "        progressVolumes",
    "        score",
    "        media {",
    "          id",
    "          title {",
    "            romaji",
    "            english",
    "            native",
    "          }",
    "          status",
    "          format",
    "          chapters",
    "          volumes",
    "          coverImage {",
    "            medium",
    "            large",
    "          }",
    "          siteUrl",
    "          genres",
    "          averageScore",
    "        }",
    "      }",
    "    }",
    "  }",
    "}"
  ].join("\n")

  return JSON.stringify({
    query: query,
    variables: { userName: username }
  })
}

function buildAniListSearchQuery(searchQuery) {
  var query = [
    "query ($search: String) {",
    "  Page(page: 1, perPage: 12) {",
    "    media(search: $search, sort: POPULARITY_DESC) {",
    "      id",
    "      type",
    "      title {",
    "        romaji",
    "        english",
    "        native",
    "      }",
    "      format",
    "      status",
    "      episodes",
    "      chapters",
    "      nextAiringEpisode {",
    "        episode",
    "        airingAt",
    "        timeUntilAiring",
    "      }",
    "      coverImage {",
    "        medium",
    "        large",
    "      }",
    "      siteUrl",
    "      averageScore",
    "      genres",
    "    }",
    "  }",
    "}"
  ].join("\n")

  return JSON.stringify({
    query: query,
    variables: { search: searchQuery }
  })
}

// ----------------------------------------------------------- Data Normalization

function getTitle(media) {
  if (!media) return "Unknown Title"
  if (typeof media.title === "string") return media.title
  if (media.title && typeof media.title === "object") {
    return media.title.english || media.title.romaji || media.title.native || "Unknown Title"
  }
  return media.anime_title_eng || media.anime_title || "Unknown Title"
}

function getCover(media) {
  if (!media) return ""
  if (media.coverImage) {
    return media.coverImage.large || media.coverImage.medium || ""
  }
  return media.anime_image_path || ""
}

// ----------------------------------------------------------- AniList Parser

function parseAniListResponse(rawJson, trackerState) {
  var result = {
    userName: "",
    userAvatar: "",
    userBanner: "",
    upcomingAnime: [],
    watchingAnime: [],
    readingManga: [],
    recentDrops: [],
    newDrops: [],
    updatedTrackerState: null,
    error: null
  }

  if (!rawJson) {
    result.error = "No response from AniList"
    return result
  }

  var data = null
  try {
    data = typeof rawJson === "string" ? JSON.parse(rawJson) : rawJson
  } catch (e) {
    result.error = "Invalid AniList response format"
    return result
  }

  if (data.errors && data.errors.length > 0) {
    var firstErr = data.errors[0]
    var msg = String(firstErr.message || "").toLowerCase()
    if (firstErr.status === 404 || msg.indexOf("not found") !== -1) {
      result.error = "User not found on AniList"
    } else if (msg.indexOf("private") !== -1) {
      result.error = "AniList profile or list is private"
    } else {
      result.error = firstErr.message || "AniList API error"
    }
    return result
  }

  if (data.data && data.data.user) {
    result.userName = data.data.user.name || ""
    result.userBanner = data.data.user.bannerImage || ""
    if (data.data.user.avatar) {
      result.userAvatar = data.data.user.avatar.large || data.data.user.avatar.medium || ""
    }
  } else if (!data.data || !data.data.user) {
    result.error = "User not found on AniList"
    return result
  }

  var nowSec = Math.floor(Date.now() / 1000)
  var animeLists = (data.data && data.data.anime && data.data.anime.lists) || []
  var mangaLists = (data.data && data.data.manga && data.data.manga.lists) || []

  var seenIds = {}

  // Parse Anime Lists (CURRENT / Watching only)
  for (var i = 0; i < animeLists.length; i++) {
    var list = animeLists[i]
    var listStatus = (list.status || "").toUpperCase()
    if (listStatus !== "CURRENT") continue
    var entries = list.entries || []

    for (var j = 0; j < entries.length; j++) {
      var entry = entries[j]
      var media = entry.media
      if (!media || seenIds["anime_" + media.id]) continue
      seenIds["anime_" + media.id] = true

      var title = getTitle(media)
      var cover = getCover(media)
      var nextEp = media.nextAiringEpisode
      var currentNextEp = nextEp ? nextEp.episode : null

      var item = {
        id: "al_a_" + media.id,
        mediaId: media.id,
        type: "ANIME",
        title: title,
        romaji: (media.title && media.title.romaji) || "",
        english: (media.title && media.title.english) || "",
        cover: cover,
        progress: entry.progress || 0,
        totalEpisodes: media.episodes || null,
        status: media.status || "UNKNOWN",
        userStatus: listStatus,
        score: entry.score || 0,
        siteUrl: media.siteUrl || ("https://anilist.co/anime/" + media.id),
        genres: media.genres || [],
        averageScore: media.averageScore || 0,
        nextEpisode: currentNextEp,
        airingAt: nextEp ? nextEp.airingAt : null,
        timeUntilAiring: nextEp ? (nextEp.airingAt - nowSec) : null
      }

      result.watchingAnime.push(item)

      // If there is an upcoming episode in the future, add to upcoming list
      if (nextEp && nextEp.airingAt) {
        var diff = nextEp.airingAt - nowSec
        if (diff > 0) {
          result.upcomingAnime.push(item)
        }
      }
    }
  }

  // State-transition drop detection (shared with MAL enrichment mode)
  var drops = detectDrops(result.watchingAnime, trackerState)
  result.recentDrops = drops.recentDrops
  result.newDrops = drops.newDrops
  result.updatedTrackerState = drops.updatedTrackerState

  // Sort upcoming anime by closest airing time
  result.upcomingAnime.sort(function(a, b) {
    return (a.airingAt || 0) - (b.airingAt || 0)
  })

  // Parse Manga Lists (CURRENT / Reading only)
  for (var m = 0; m < mangaLists.length; m++) {
    var mList = mangaLists[m]
    var mStatus = (mList.status || "").toUpperCase()
    if (mStatus !== "CURRENT") continue
    var mEntries = mList.entries || []

    for (var k = 0; k < mEntries.length; k++) {
      var mEntry = mEntries[k]
      var mMedia = mEntry.media
      if (!mMedia || seenIds["manga_" + mMedia.id]) continue
      seenIds["manga_" + mMedia.id] = true

      var mItem = {
        id: "al_m_" + mMedia.id,
        mediaId: mMedia.id,
        type: "MANGA",
        title: getTitle(mMedia),
        cover: getCover(mMedia),
        progress: mEntry.progress || 0,
        progressVolumes: mEntry.progressVolumes || 0,
        totalChapters: mMedia.chapters || null,
        totalVolumes: mMedia.volumes || null,
        status: mMedia.status || "UNKNOWN",
        userStatus: mStatus,
        score: mEntry.score || 0,
        siteUrl: mMedia.siteUrl || ("https://anilist.co/manga/" + mMedia.id),
        genres: mMedia.genres || [],
        averageScore: mMedia.averageScore || 0
      }

      result.readingManga.push(mItem)
    }
  }

  // Sort watching anime: upcoming airing first (closest airing date), then active releasing, then others
  result.watchingAnime.sort(function(a, b) {
    var aHasAiring = (a.airingAt && a.airingAt > nowSec) ? 1 : 0
    var bHasAiring = (b.airingAt && b.airingAt > nowSec) ? 1 : 0
    if (aHasAiring !== bHasAiring) return bHasAiring - aHasAiring
    if (aHasAiring && bHasAiring) return a.airingAt - b.airingAt
    if (a.status === "RELEASING" && b.status !== "RELEASING") return -1
    if (b.status === "RELEASING" && a.status !== "RELEASING") return 1
    return 0
  })

  // Sort reading manga: releasing first, then others
  result.readingManga.sort(function(a, b) {
    if (a.status === "RELEASING" && b.status !== "RELEASING") return -1
    if (b.status === "RELEASING" && a.status !== "RELEASING") return 1
    return 0
  })

  return result
}

// ----------------------------------------------------------- Drop Detection & Enrichment

// Shared state-transition drop detection used by both AniList and MAL modes.
// watchingAnime items need: mediaId, title, cover, siteUrl, status, nextEpisode.
function detectDrops(watchingAnime, trackerState) {
  var seenMap = (trackerState && trackerState.seen) ? trackerState.seen : ((trackerState && typeof trackerState === "object") ? trackerState : {})
  var lastEpMap = (trackerState && trackerState.lastEp) ? trackerState.lastEp : {}
  var isInitialized = trackerState ? (trackerState.initialized !== false && (Object.keys(lastEpMap).length > 0 || Object.keys(seenMap).length > 0)) : false
  var nowSec = Math.floor(Date.now() / 1000)
  var newLastEpMap = {}
  var recentDrops = []
  var newDrops = []
  var processedIds = {}

  for (var i = 0; i < watchingAnime.length; i++) {
    var item = watchingAnime[i]
    var mediaIdStr = String(item.mediaId)
    if (processedIds[mediaIdStr]) continue
    processedIds[mediaIdStr] = true

    // Normalize: undefined/null/0 all mean "no upcoming episode known"
    var currentNextEp = item.nextEpisode > 0 ? item.nextEpisode : null
    var prevEp = lastEpMap[mediaIdStr]

    if (isInitialized && prevEp !== undefined && prevEp !== null && prevEp !== "FINISHED") {
      if (currentNextEp !== null && currentNextEp > prevEp) {
        // Episodes from prevEp up to (currentNextEp - 1) have aired
        for (var epNum = prevEp; epNum < currentNextEp; epNum++) {
          var dropKey = item.mediaId + ":" + epNum
          var isNew = !seenMap[dropKey]
          var dropItem = {
            id: dropKey,
            mediaId: item.mediaId,
            type: "ANIME",
            title: item.title,
            episode: epNum,
            airedAt: nowSec,
            cover: item.cover,
            siteUrl: item.siteUrl,
            isNew: isNew
          }
          recentDrops.push(dropItem)
          if (isNew) {
            newDrops.push(dropItem)
          }
        }
      } else if (currentNextEp === null && item.status === "FINISHED" && prevEp !== "FINISHED") {
        // Show completed while we were away: catch up every episode after
        // prevEp, up to the known total (falls back to prevEp alone when the
        // total episode count is unknown).
        var lastAired = (item.totalEpisodes && item.totalEpisodes > prevEp) ? item.totalEpisodes : prevEp
        for (var finEp = prevEp; finEp <= lastAired; finEp++) {
          var finKey = item.mediaId + ":" + finEp
          var finIsNew = !seenMap[finKey]
          var finDrop = {
            id: finKey,
            mediaId: item.mediaId,
            type: "ANIME",
            title: item.title,
            episode: finEp,
            airedAt: nowSec,
            cover: item.cover,
            siteUrl: item.siteUrl,
            isNew: finIsNew
          }
          recentDrops.push(finDrop)
          if (finIsNew) {
            newDrops.push(finDrop)
          }
        }
      }
    }

    // Record current next episode for future transitions
    newLastEpMap[mediaIdStr] = currentNextEp !== null ? currentNextEp : (item.status === "FINISHED" ? "FINISHED" : (prevEp || null))
  }

  // Prune seenMap: only keep seen drops for active CURRENT watching anime
  var activeAnimeIds = {}
  for (var a = 0; a < watchingAnime.length; a++) {
    activeAnimeIds[String(watchingAnime[a].mediaId)] = true
  }

  var prunedSeenMap = {}
  for (var dropKey in seenMap) {
    if (Object.prototype.hasOwnProperty.call(seenMap, dropKey)) {
      var showMediaId = dropKey.split(":")[0]
      if (activeAnimeIds[showMediaId]) {
        prunedSeenMap[dropKey] = seenMap[dropKey]
      }
    }
  }

  recentDrops.sort(function(a, b) {
    if (a.mediaId !== b.mediaId) return String(a.title).localeCompare(String(b.title))
    return (b.episode || 0) - (a.episode || 0)
  })

  return {
    recentDrops: recentDrops,
    newDrops: newDrops,
    updatedTrackerState: {
      seen: prunedSeenMap,
      lastEp: newLastEpMap,
      initialized: true
    }
  }
}

// Batch lookup of airing schedules by MAL ID (exact match, no title search).
function buildAniListMalEnrichQuery(malIds) {
  var query = [
    "query ($malIds: [Int]) {",
    "  Page(page: 1, perPage: 50) {",
    "    media(idMal_in: $malIds, type: ANIME) {",
    "      id",
    "      idMal",
    "      status",
    "      format",
    "      episodes",
    "      nextAiringEpisode {",
    "        episode",
    "        airingAt",
    "        timeUntilAiring",
    "      }",
    "      coverImage {",
    "        medium",
    "        large",
    "      }",
    "      siteUrl",
    "      genres",
    "      averageScore",
    "    }",
    "  }",
    "}"
  ].join("\n")

  return JSON.stringify({
    query: query,
    variables: { malIds: malIds }
  })
}

// Parses the enrichment response into a map keyed by MAL ID.
function parseEnrichResponse(rawJson) {
  var map = {}
  if (!rawJson) return map

  var data = null
  try {
    data = typeof rawJson === "string" ? JSON.parse(rawJson) : rawJson
  } catch (e) {
    return map
  }

  if (!data || (data.errors && data.errors.length > 0)) return map

  var mediaList = (data.data && data.data.Page && data.data.Page.media) || []
  for (var i = 0; i < mediaList.length; i++) {
    var m = mediaList[i]
    if (!m || m.idMal === null || m.idMal === undefined) continue
    var nextEp = m.nextAiringEpisode
    map[String(m.idMal)] = {
      id: m.id,
      status: m.status || "UNKNOWN",
      totalEpisodes: m.episodes || null,
      nextEpisode: nextEp ? nextEp.episode : null,
      airingAt: nextEp ? nextEp.airingAt : null,
      cover: m.coverImage ? (m.coverImage.large || m.coverImage.medium || "") : "",
      siteUrl: m.siteUrl || "",
      genres: m.genres || [],
      averageScore: m.averageScore || 0
    }
  }

  return map
}

// Fills MAL anime entries with AniList schedule data and builds the upcoming list.
function applyEnrichment(animeList, enrichMap) {
  var list = Array.isArray(animeList) ? animeList : []
  var map = enrichMap || {}
  var nowSec = Math.floor(Date.now() / 1000)
  var upcoming = []

  for (var i = 0; i < list.length; i++) {
    var item = list[i]
    var en = map[String(item.mediaId)]
    if (!en) continue

    item.anilistId = en.id
    if (en.totalEpisodes && !item.totalEpisodes) item.totalEpisodes = en.totalEpisodes
    if (en.status) item.status = en.status
    if (en.cover) item.cover = en.cover
    if (en.siteUrl) item.anilistUrl = en.siteUrl
    if (en.genres && en.genres.length > 0) item.genres = en.genres
    if (en.averageScore) item.averageScore = en.averageScore
    item.nextEpisode = en.nextEpisode
    item.airingAt = en.airingAt
    item.timeUntilAiring = en.airingAt ? (en.airingAt - nowSec) : null

    if (en.nextEpisode !== null && en.airingAt && en.airingAt > nowSec) {
      upcoming.push(item)
    }
  }

  upcoming.sort(function(a, b) {
    return (a.airingAt || 0) - (b.airingAt || 0)
  })

  list.sort(function(a, b) {
    var aHasAiring = (a.airingAt && a.airingAt > nowSec) ? 1 : 0
    var bHasAiring = (b.airingAt && b.airingAt > nowSec) ? 1 : 0
    if (aHasAiring !== bHasAiring) return bHasAiring - aHasAiring
    if (aHasAiring && bHasAiring) return a.airingAt - b.airingAt
    if (a.status === "RELEASING" && b.status !== "RELEASING") return -1
    if (b.status === "RELEASING" && a.status !== "RELEASING") return 1
    return 0
  })

  return { anime: list, upcoming: upcoming }
}

// ----------------------------------------------------------- MAL Parser

function parseMALListResponse(rawJson) {
  var list = []
  if (!rawJson) {
    list.error = "No response from MyAnimeList"
    return list
  }

  var data = null
  try {
    data = typeof rawJson === "string" ? JSON.parse(rawJson) : rawJson
  } catch (e) {
    list.error = "Invalid MAL response format"
    return list
  }

  if (data && data.errors && data.errors.length > 0) {
    var msg = String(data.errors[0].message || "").toLowerCase()
    if (msg.indexOf("private") !== -1) {
      list.error = "MAL watchlist is private"
    } else if (msg.indexOf("invalid") !== -1 || msg.indexOf("not found") !== -1) {
      list.error = "User not found on MyAnimeList"
    } else {
      list.error = data.errors[0].message || "MyAnimeList error"
    }
    return list
  }

  if (!Array.isArray(data)) {
    list.error = "User not found or watchlist unavailable on MAL"
    return list
  }

  for (var i = 0; i < data.length; i++) {
    var row = data[i]
    if (!row) continue
    if (row.status !== undefined && row.status !== 1 && row.status !== "1") continue
    var title = row.anime_title_eng || row.anime_title || "Unknown"
    list.push({
      id: "mal_a_" + row.anime_id,
      mediaId: row.anime_id,
      type: "ANIME",
      title: title,
      romaji: row.anime_title || "",
      english: row.anime_title_eng || "",
      cover: row.anime_image_path || "",
      progress: row.num_watched_episodes || 0,
      totalEpisodes: row.anime_num_episodes || null,
      status: row.anime_airing_status === 1 ? "RELEASING" : (row.anime_airing_status === 2 ? "FINISHED" : "NOT_YET_RELEASED"),
      score: row.score || 0,
      siteUrl: "https://myanimelist.net" + (row.anime_url || ("/anime/" + row.anime_id)),
      nextEpisode: null,
      airingAt: null,
      timeUntilAiring: null,
      source: "MAL"
    })
  }

  return list
}

function parseMALMangaResponse(rawJson) {
  var list = []
  if (!rawJson) {
    list.error = "No response from MyAnimeList"
    return list
  }

  var data = null
  try {
    data = typeof rawJson === "string" ? JSON.parse(rawJson) : rawJson
  } catch (e) {
    list.error = "Invalid MAL response format"
    return list
  }

  if (data && data.errors && data.errors.length > 0) {
    var msg = String(data.errors[0].message || "").toLowerCase()
    if (msg.indexOf("private") !== -1) {
      list.error = "MAL manga list is private"
    } else if (msg.indexOf("invalid") !== -1 || msg.indexOf("not found") !== -1) {
      list.error = "User not found on MyAnimeList"
    } else {
      list.error = data.errors[0].message || "MyAnimeList error"
    }
    return list
  }

  if (!Array.isArray(data)) {
    list.error = "User not found or manga list unavailable on MAL"
    return list
  }

  for (var i = 0; i < data.length; i++) {
    var row = data[i]
    if (!row) continue
    if (row.status !== undefined && row.status !== 1 && row.status !== "1") continue
    var title = row.manga_english || row.manga_title || "Unknown"
    list.push({
      id: "mal_m_" + row.manga_id,
      mediaId: row.manga_id,
      type: "MANGA",
      title: title,
      romaji: row.manga_title || "",
      english: row.manga_english || "",
      cover: row.manga_image_path || "",
      progress: row.num_read_chapters || 0,
      totalChapters: row.manga_num_chapters || null,
      status: row.manga_publishing_status === 1 ? "RELEASING" : (row.manga_publishing_status === 2 ? "FINISHED" : "NOT_YET_RELEASED"),
      score: row.score || 0,
      siteUrl: "https://myanimelist.net" + (row.manga_url || ("/manga/" + row.manga_id)),
      source: "MAL"
    })
  }

  return list
}

function parseMALUserAvatar(html) {
  if (!html || typeof html !== "string") return ""
  var match = html.match(/<div class="user-image[^>]*>[\s\S]*?<img[^>]+(?:data-src|src)="([^">]+)"/i)
  return match ? match[1] : ""
}


// Splits a curl response that was captured with `-w '\n%{http_code}'` into
// its body and numeric status. With --fail, curl suppresses error bodies but
// still emits the write-out string, so a revoked token surfaces here as
// { status: "401", body: "" } instead of being indistinguishable from a
// network failure. No trailing code (plain body / empty input) -> status "".
function splitCurlHttpStatus(rawText) {
  var out = { status: "", body: rawText || "" }
  if (!rawText) return out
  var idx = String(rawText).lastIndexOf("\n")
  if (idx < 0) return out
  var code = String(rawText).substring(idx + 1).trim()
  if (/^\d{3}$/.test(code)) {
    out.status = code
    out.body = String(rawText).substring(0, idx)
  }
  return out
}

// ----------------------------------------------------------- Simkl Provider

// Simkl auth model: a single app-wide client_id (public) plus a per-user
// access token obtained through the PIN/device flow. No client_secret is
// involved anywhere; tokens live ~5 years until revoked.
var SIMKL_API_BASE = "https://api.simkl.com"
var SIMKL_CALENDAR_URL = "https://data.simkl.in/calendar/anime.json"
var SIMKL_APP_NAME = "anisync"
var SIMKL_APP_VERSION = "1.2.0"

// client_id / app-name / app-version are required URL parameters on every
// Simkl request (see api.simkl.org/conventions/headers).
function simklCommonParams(clientId) {
  return "client_id=" + encodeURIComponent(String(clientId || "")) +
    "&app-name=" + SIMKL_APP_NAME +
    "&app-version=" + SIMKL_APP_VERSION
}

// Step 1 of the PIN flow: request a short user code the owner types at
// simkl.com/pin. GET https://api.simkl.com/oauth/pin?client_id=…
function buildSimklPinStartUrl(clientId) {
  return SIMKL_API_BASE + "/oauth/pin?" + simklCommonParams(clientId)
}

function parseSimklPinStart(rawJson) {
  var out = {
    ok: false,
    userCode: "",
    verificationUrl: "https://simkl.com/pin",
    expiresInSeconds: 900,
    pollIntervalSecs: 5,
    error: null
  }
  if (!rawJson) {
    out.error = "No response from Simkl"
    return out
  }
  var data = null
  try {
    data = typeof rawJson === "string" ? JSON.parse(rawJson) : rawJson
  } catch (e) {
    data = null
  }
  if (!data || String(data.result || "").toUpperCase() !== "OK" || !data.user_code) {
    out.error = "Could not start Simkl sign-in"
    return out
  }
  out.ok = true
  out.userCode = String(data.user_code)
  if (data.verification_uri) out.verificationUrl = String(data.verification_uri)
  if (data.expires_in) out.expiresInSeconds = parseInt(data.expires_in, 10) || 900
  if (data.interval) out.pollIntervalSecs = parseInt(data.interval, 10) || 5
  return out
}

// Step 2 of the PIN flow: poll every interval seconds until approved.
function buildSimklPinPollUrl(userCode, clientId) {
  return SIMKL_API_BASE + "/oauth/pin/" + encodeURIComponent(String(userCode || "")) + "?" + simklCommonParams(clientId)
}

// States: "pending" (keep polling), "authorized" (token arrived),
// "expired" (stop and re-issue). A reply carrying device_code means the
// poll fell through to the create-a-new-code branch — the original code
// was consumed or never existed, so polling must stop.
function parseSimklPinPoll(rawJson) {
  var out = { state: "pending", accessToken: "" }
  if (!rawJson) return out
  var data = null
  try {
    data = typeof rawJson === "string" ? JSON.parse(rawJson) : rawJson
  } catch (e) {
    data = null
  }
  if (!data) return out
  var res = String(data.result || "").toUpperCase()
  if (res === "OK" && data.access_token) {
    out.state = "authorized"
    out.accessToken = String(data.access_token)
  } else if (data.device_code) {
    out.state = "expired"
  }
  return out
}

// Profile lookup: POST /users/settings returns name, avatar, plan type.
// (POST for historical reasons — no body.)
function buildSimklUserSettingsUrl(clientId) {
  return SIMKL_API_BASE + "/users/settings?" + simklCommonParams(clientId)
}

function parseSimklUserProfile(rawJson) {
  var out = { userName: "", avatar: "", accountType: "", error: null }
  if (!rawJson) {
    out.error = "No response from Simkl"
    return out
  }
  var data = null
  try {
    data = typeof rawJson === "string" ? JSON.parse(rawJson) : rawJson
  } catch (e) {
    data = null
  }
  if (!data || !data.user) {
    out.error = "Could not read Simkl profile"
    return out
  }
  out.userName = String(data.user.name || "")
  out.avatar = String(data.user.avatar || "")
  out.accountType = String((data.account && data.account.type) || "")
  return out
}

// Watching list: GET /sync/all-items/:type/watching. The default rich
// summary already carries counts, ratings, poster paths, and mapped
// external ids; next_watch_info=yes attaches next_to_watch_info.
// type is "anime" or "shows" — identical row shape, different top-level
// response key ("anime" vs "shows").
function buildSimklListUrl(type, clientId) {
  return SIMKL_API_BASE + "/sync/all-items/" + type + "/watching?" + simklCommonParams(clientId) + "&next_watch_info=yes"
}

// Public Cloudflare-cached calendar files: episodes airing from yesterday
// through the next ~33 days. No auth required. One file per type.
var SIMKL_TV_CALENDAR_URL = "https://data.simkl.in/calendar/tv.json"

function buildSimklCalendarUrl() {
  return SIMKL_CALENDAR_URL
}

function buildSimklTvCalendarUrl() {
  return SIMKL_TV_CALENDAR_URL
}

// Flattens the calendar array into a schedule lookup keyed by both Simkl
// ("s<id>") and MAL ("m<id>") ids, since watchlist entries carry both.
function parseSimklCalendar(rawJson) {
  var map = {}
  if (!rawJson) return map
  var data = null
  try {
    data = typeof rawJson === "string" ? JSON.parse(rawJson) : rawJson
  } catch (e) {
    data = null
  }
  if (!Array.isArray(data)) return map

  for (var i = 0; i < data.length; i++) {
    var row = data[i]
    if (!row || !row.date || !row.episode || row.episode.episode === undefined || row.episode.episode === null) continue
    var epochMs = Date.parse(String(row.date))
    if (isNaN(epochMs)) continue
    var info = {
      episode: row.episode.episode,
      airingAt: Math.floor(epochMs / 1000),
      siteUrl: (row.episode && row.episode.url) || row.url || ""
    }
    var ids = row.ids || {}
    var keys = []
    if (ids.simkl_id) keys.push("s" + ids.simkl_id)
    if (ids.mal) keys.push("m" + ids.mal)
    if (ids.tmdb) keys.push("t" + ids.tmdb)

    for (var k = 0; k < keys.length; k++) {
      var key = keys[k]
      if (!map[key]) {
        map[key] = []
      }
      map[key].push(info)
    }
  }

  for (var k in map) {
    if (Object.prototype.hasOwnProperty.call(map, k)) {
      map[k].sort(function(a, b) {
        return (a.airingAt || 0) - (b.airingAt || 0)
      })
    }
  }

  return map
}

// Simkl returns poster *paths* ("74/74415673dcdc9cdd"), not URLs.
// Posters are served as webp at simkl.in; placeholder covers gaps.
function simklPosterUrl(posterPath) {
  if (!posterPath) return "https://simkl.in/poster_no_pic_c.png"
  return "https://simkl.in/posters/" + posterPath + "_w.webp"
}

// Normalizes GET /sync/all-items/:type/watching rows into the shared item
// shape used by AniList/MAL modes, joining exact airing times from the CDN
// calendars (fallback: the entry's own next_to_watch_info date). Accepts
// anime and TV shows; movies have no "watching" state on Simkl so they are
// out of scope. Manga does not exist on Simkl — readingManga stays empty.
function parseSimklResponse(rawJson, trackerState, calendarMap, listType) {
  var type = listType === "shows" ? "shows" : "anime"
  var result = {
    userName: "",
    userAvatar: "",
    userBanner: "",
    upcomingAnime: [],
    watchingAnime: [],
    readingManga: [],
    recentDrops: [],
    newDrops: [],
    updatedTrackerState: null,
    error: null
  }

  if (!rawJson) {
    result.error = "No response from Simkl"
    return result
  }

  var data = null
  try {
    data = typeof rawJson === "string" ? JSON.parse(rawJson) : rawJson
  } catch (e) {
    data = null
  }
  if (!data) {
    result.error = "Invalid Simkl response format"
    return result
  }
  if (data.error) {
    result.error = data.error_message || "Simkl API error"
    return result
  }

  // Anime responses key rows under "anime"; TV show responses under "shows".
  var entries = Array.isArray(data[type]) ? data[type] : []
  var cal = calendarMap || {}
  var nowSec = Math.floor(Date.now() / 1000)

  for (var i = 0; i < entries.length; i++) {
    var row = entries[i]
    if (!row) continue
    var show = row.anime || row.show || {}
    var ids = show.ids || {}
    var simklId = ids.simkl !== undefined ? ids.simkl : ids.simkl_id
    if (simklId === undefined || simklId === null) continue
    simklId = Number(simklId)

    var title = String(show.title || "Unknown")
    var totalEpisodes = row.total_episodes_count || null
    // not_aired_episodes_count is the cleanest release-status signal the
    // watchlist summary offers: >0 still airing, 0 with a known total means
    // everything has aired (drives finale catch-up in detectDrops).
    var notAired = row.not_aired_episodes_count
    var status = ""
    if (typeof notAired === "number") {
      status = notAired > 0 ? "RELEASING" : (totalEpisodes ? "FINISHED" : "")
    }

    var item = {
      id: "sk_" + (type === "shows" ? "s_" : "a_") + simklId,
      mediaId: simklId,
      type: type === "shows" ? "SHOW" : "ANIME",
      title: title,
      romaji: title,
      english: "",
      cover: simklPosterUrl(show.poster),
      progress: row.watched_episodes_count || 0,
      totalEpisodes: totalEpisodes,
      status: status,
      userStatus: "CURRENT",
      score: row.user_rating || 0,
      siteUrl: "https://simkl.com/" + (type === "shows" ? "tv/" : "anime/") + simklId,
      genres: [],
      averageScore: 0,
      malId: ids.mal !== undefined && ids.mal !== null ? Number(ids.mal) : null,
      anilistId: ids.anilist !== undefined && ids.anilist !== null ? Number(ids.anilist) : null,
      tmdbId: ids.tmdb !== undefined && ids.tmdb !== null && ids.tmdb !== "" ? Number(ids.tmdb) : null,
      nextEpisode: null,
      airingAt: null,
      timeUntilAiring: null,
      source: "SIMKL"
    }

    // Schedule resolution: exact calendar match first (by Simkl id, then
    // MAL id, then TMDB id for TV shows), else the entry's own next-episode date.
    var calEpisodes = cal["s" + simklId]
    if (!calEpisodes && item.malId !== null) calEpisodes = cal["m" + item.malId]
    if (!calEpisodes && type === "shows" && item.tmdbId !== null) {
      calEpisodes = cal["t" + item.tmdbId]
    }

    var calInfo = null
    if (Array.isArray(calEpisodes) && calEpisodes.length > 0) {
      // Find the earliest upcoming episode in the future (airingAt > nowSec)
      for (var epIdx = 0; epIdx < calEpisodes.length; epIdx++) {
        if (calEpisodes[epIdx].airingAt > nowSec) {
          calInfo = calEpisodes[epIdx]
          break
        }
      }
    } else if (calEpisodes && typeof calEpisodes === "object" && calEpisodes.airingAt > nowSec) {
      calInfo = calEpisodes
    }

    if (calInfo) {
      item.nextEpisode = calInfo.episode
      item.airingAt = calInfo.airingAt
      if (calInfo.siteUrl) item.siteUrl = calInfo.siteUrl
    } else if (row.next_to_watch_info && row.next_to_watch_info.date) {
      var ntwMs = Date.parse(String(row.next_to_watch_info.date))
      if (!isNaN(ntwMs)) {
        var ntwSec = Math.floor(ntwMs / 1000)
        if (ntwSec > nowSec) {
          item.airingAt = ntwSec
          if (row.next_to_watch_info.episode !== undefined && row.next_to_watch_info.episode !== null) {
            item.nextEpisode = row.next_to_watch_info.episode
          }
        }
      }
    }
    if (item.airingAt) item.timeUntilAiring = item.airingAt - nowSec

    result.watchingAnime.push(item)

    if (item.airingAt && item.airingAt > nowSec && item.nextEpisode) {
      result.upcomingAnime.push(item)
    }
  }

  // Shared state-transition drop detection (identical contract to AniList mode)
  var drops = detectDrops(result.watchingAnime, trackerState)
  result.recentDrops = drops.recentDrops
  result.newDrops = drops.newDrops
  result.updatedTrackerState = drops.updatedTrackerState

  result.upcomingAnime.sort(function(a, b) {
    return (a.airingAt || 0) - (b.airingAt || 0)
  })

  result.watchingAnime.sort(function(a, b) {
    var aHasAiring = (a.airingAt && a.airingAt > nowSec) ? 1 : 0
    var bHasAiring = (b.airingAt && b.airingAt > nowSec) ? 1 : 0
    if (aHasAiring !== bHasAiring) return bHasAiring - aHasAiring
    if (aHasAiring && bHasAiring) return a.airingAt - b.airingAt
    if (a.status === "RELEASING" && b.status !== "RELEASING") return -1
    if (b.status === "RELEASING" && a.status !== "RELEASING") return 1
    return 0
  })

  return result
}



// ----------------------------------------------------------- Search Parser

function parseSearchResponse(rawJson) {
  var list = []
  if (!rawJson) return list

  var data = null
  try {
    data = typeof rawJson === "string" ? JSON.parse(rawJson) : rawJson
  } catch (e) {
    return list
  }

  var mediaList = (data.data && data.data.Page && data.data.Page.media) || []
  var nowSec = Math.floor(Date.now() / 1000)

  for (var i = 0; i < mediaList.length; i++) {
    var media = mediaList[i]
    if (!media) continue
    var nextEp = media.nextAiringEpisode
    list.push({
      id: "search_" + media.id,
      mediaId: media.id,
      type: media.type || "ANIME",
      title: getTitle(media),
      cover: getCover(media),
      format: media.format || "",
      status: media.status || "",
      episodes: media.episodes || null,
      chapters: media.chapters || null,
      averageScore: media.averageScore || null,
      siteUrl: media.siteUrl || ("https://anilist.co/" + (media.type ? media.type.toLowerCase() : "anime") + "/" + media.id),
      nextEpisode: nextEp ? nextEp.episode : null,
      airingAt: nextEp ? nextEp.airingAt : null,
      timeUntilAiring: nextEp ? (nextEp.airingAt - nowSec) : null
    })
  }

  return list
}

// ----------------------------------------------------------- Time Formatters

function formatCountdown(targetEpochSecs) {
  if (!targetEpochSecs) return ""
  var nowSec = Math.floor(Date.now() / 1000)
  var diffSec = targetEpochSecs - nowSec

  if (diffSec <= 0) return "Just released!"

  var days = Math.floor(diffSec / 86400)
  var hours = Math.floor((diffSec % 86400) / 3600)
  var mins = Math.floor((diffSec % 3600) / 60)

  if (days > 7) {
    return "in " + days + " days"
  }
  if (days >= 1) {
    if (hours > 0) return "in " + days + "d " + hours + "h"
    return "in " + days + "d"
  }
  if (hours >= 1) {
    if (mins > 0) return "in " + hours + "h " + mins + "m"
    return "in " + hours + "h"
  }
  return "in " + Math.max(1, mins) + "m"
}

function formatShortTicker(item) {
  if (!item) return ""
  var title = item.title || ""
  if (title.length > 13) {
    title = title.substring(0, 11) + "…"
  }
  var epStr = item.nextEpisode ? (" Ep " + item.nextEpisode) : ""
  var timeStr = formatCountdown(item.airingAt)
  return title + epStr + " · " + timeStr
}

function formatAiringTime(epochSecs) {
  if (!epochSecs) return ""
  var date = new Date(epochSecs * 1000)
  var now = new Date()

  var sameDay = date.getFullYear() === now.getFullYear() &&
                date.getMonth() === now.getMonth() &&
                date.getDate() === now.getDate()

  var tomorrow = new Date(now.getTime() + 86400000)
  var isTomorrow = date.getFullYear() === tomorrow.getFullYear() &&
                    date.getMonth() === tomorrow.getMonth() &&
                    date.getDate() === tomorrow.getDate()

  var hours = date.getHours()
  var mins = date.getMinutes()
  var ampm = hours >= 12 ? "PM" : "AM"
  var h12 = hours % 12 || 12
  var mStr = mins < 10 ? "0" + mins : String(mins)
  var timeStr = h12 + ":" + mStr + " " + ampm

  if (sameDay) return "Today at " + timeStr
  if (isTomorrow) return "Tomorrow at " + timeStr

  var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  return days[date.getDay()] + ", " + months[date.getMonth()] + " " + date.getDate() + " · " + timeStr
}

function formatRelativeTime(epochSecs) {
  if (!epochSecs) return ""
  var nowSec = Math.floor(Date.now() / 1000)
  var diff = nowSec - epochSecs

  if (diff < 60) return "Just now"
  if (diff < 3600) return Math.floor(diff / 60) + "m ago"
  if (diff < 86400) return Math.floor(diff / 3600) + "h ago"
  var days = Math.floor(diff / 86400)
  return days === 1 ? "Yesterday" : (days + " days ago")
}

// ----------------------------------------------------------- Module Export

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    buildAniListUserQuery: buildAniListUserQuery,
    buildAniListSearchQuery: buildAniListSearchQuery,
    parseAniListResponse: parseAniListResponse,
    detectDrops: detectDrops,
    buildAniListMalEnrichQuery: buildAniListMalEnrichQuery,
    parseEnrichResponse: parseEnrichResponse,
    applyEnrichment: applyEnrichment,
    parseMALListResponse: parseMALListResponse,
    parseMALMangaResponse: parseMALMangaResponse,
    parseMALUserAvatar: parseMALUserAvatar,
    parseSearchResponse: parseSearchResponse,
    splitCurlHttpStatus: splitCurlHttpStatus,
    buildSimklPinStartUrl: buildSimklPinStartUrl,
    parseSimklPinStart: parseSimklPinStart,
    buildSimklPinPollUrl: buildSimklPinPollUrl,
    parseSimklPinPoll: parseSimklPinPoll,
    buildSimklUserSettingsUrl: buildSimklUserSettingsUrl,
    parseSimklUserProfile: parseSimklUserProfile,
    buildSimklListUrl: buildSimklListUrl,
    buildSimklCalendarUrl: buildSimklCalendarUrl,
    buildSimklTvCalendarUrl: buildSimklTvCalendarUrl,
    parseSimklCalendar: parseSimklCalendar,
    simklPosterUrl: simklPosterUrl,
    parseSimklResponse: parseSimklResponse,
    formatCountdown: formatCountdown,
    formatShortTicker: formatShortTicker,
    formatAiringTime: formatAiringTime,
    formatRelativeTime: formatRelativeTime,
    getTitle: getTitle,
    getCover: getCover
  }
}
