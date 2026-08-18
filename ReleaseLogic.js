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
    "  anime: MediaListCollection(userName: $userName, type: ANIME) {",
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
    "  manga: MediaListCollection(userName: $userName, type: MANGA) {",
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

function parseAniListResponse(rawJson, seenMap) {
  var result = {
    userName: "",
    userAvatar: "",
    userBanner: "",
    upcomingAnime: [],
    watchingAnime: [],
    planningAnime: [],
    readingManga: [],
    recentDrops: [],
    newDrops: [],
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

  // Parse Anime Lists
  for (var i = 0; i < animeLists.length; i++) {
    var list = animeLists[i]
    var listStatus = (list.status || "").toUpperCase()
    var entries = list.entries || []

    for (var j = 0; j < entries.length; j++) {
      var entry = entries[j]
      var media = entry.media
      if (!media || seenIds["anime_" + media.id]) continue
      seenIds["anime_" + media.id] = true

      var title = getTitle(media)
      var cover = getCover(media)
      var nextEp = media.nextAiringEpisode

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
        nextEpisode: nextEp ? nextEp.episode : null,
        airingAt: nextEp ? nextEp.airingAt : null,
        timeUntilAiring: nextEp ? (nextEp.airingAt - nowSec) : null
      }

      if (listStatus === "CURRENT") {
        result.watchingAnime.push(item)
      } else if (listStatus === "PLANNING") {
        result.planningAnime.push(item)
      }

      // If there's an upcoming airing episode
      if (nextEp && nextEp.airingAt) {
        var diff = nextEp.airingAt - nowSec
        if (diff > 0) {
          result.upcomingAnime.push(item)
        } else if (diff >= -172800) { // Aired within the last 48 hours
          var dropKey = media.id + ":" + nextEp.episode
          var isNew = !(seenMap && seenMap[dropKey])
          var dropItem = {
            id: dropKey,
            mediaId: media.id,
            type: "ANIME",
            title: title,
            episode: nextEp.episode,
            airedAt: nextEp.airingAt,
            cover: cover,
            siteUrl: item.siteUrl,
            isNew: isNew
          }
          result.recentDrops.push(dropItem)
          if (isNew) {
            result.newDrops.push(dropItem)
          }
        }
      }
    }
  }

  // Sort upcoming anime by closest airing time
  result.upcomingAnime.sort(function(a, b) {
    return (a.airingAt || 0) - (b.airingAt || 0)
  })

  // Sort recent drops by newest
  result.recentDrops.sort(function(a, b) {
    return (b.airedAt || 0) - (a.airedAt || 0)
  })

  // Parse Manga Lists
  for (var m = 0; m < mangaLists.length; m++) {
    var mList = mangaLists[m]
    var mStatus = (mList.status || "").toUpperCase()
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

      if (mStatus === "CURRENT" || mStatus === "PLANNING") {
        result.readingManga.push(mItem)
      }
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

function normalizeTitle(str) {
  if (!str) return ""
  return String(str).toLowerCase().replace(/[^a-z0-9]/g, "")
}

function mergeAnimeLists(aniListAnime, malAnime) {
  var ani = Array.isArray(aniListAnime) ? aniListAnime : []
  var mal = Array.isArray(malAnime) ? malAnime : []
  var map = {}
  var combined = []

  // Add all AniList entries first
  for (var i = 0; i < ani.length; i++) {
    var item = ani[i]
    var norm1 = normalizeTitle(item.title)
    var norm2 = normalizeTitle(item.romaji)
    var norm3 = normalizeTitle(item.english)
    if (norm1) map[norm1] = item
    if (norm2) map[norm2] = item
    if (norm3) map[norm3] = item
    item.source = item.source || "AniList"
    combined.push(item)
  }

  // Union with MAL entries
  for (var j = 0; j < mal.length; j++) {
    var mItem = mal[j]
    var mNorm = normalizeTitle(mItem.title)
    var mNormRom = normalizeTitle(mItem.romaji)
    var existing = map[mNorm] || map[mNormRom]

    if (existing) {
      existing.source = "AniList + MAL"
      existing.siteUrlMAL = mItem.siteUrl
      if ((mItem.progress || 0) > (existing.progress || 0)) {
        existing.progress = mItem.progress
      }
    } else {
      mItem.source = "MAL"
      combined.push(mItem)
      if (mNorm) map[mNorm] = mItem
      if (mNormRom) map[mNormRom] = mItem
    }
  }

  var nowSec = Math.floor(Date.now() / 1000)
  // Sort: upcoming airing first (closest airing date), then active releasing, then others
  combined.sort(function(a, b) {
    var aHasAiring = (a.airingAt && a.airingAt > nowSec) ? 1 : 0
    var bHasAiring = (b.airingAt && b.airingAt > nowSec) ? 1 : 0
    if (aHasAiring !== bHasAiring) return bHasAiring - aHasAiring
    if (aHasAiring && bHasAiring) return a.airingAt - b.airingAt
    if (a.status === "RELEASING" && b.status !== "RELEASING") return -1
    if (b.status === "RELEASING" && a.status !== "RELEASING") return 1
    return 0
  })

  return combined
}

function mergeMangaLists(aniListManga, malManga) {
  var ani = Array.isArray(aniListManga) ? aniListManga : []
  var mal = Array.isArray(malManga) ? malManga : []
  var map = {}
  var combined = []

  for (var i = 0; i < ani.length; i++) {
    var item = ani[i]
    var norm1 = normalizeTitle(item.title)
    var norm2 = normalizeTitle(item.romaji)
    var norm3 = normalizeTitle(item.english)
    if (norm1) map[norm1] = item
    if (norm2) map[norm2] = item
    if (norm3) map[norm3] = item
    item.source = item.source || "AniList"
    combined.push(item)
  }

  for (var j = 0; j < mal.length; j++) {
    var mItem = mal[j]
    var mNorm = normalizeTitle(mItem.title)
    var mNormRom = normalizeTitle(mItem.romaji)
    var existing = map[mNorm] || map[mNormRom]

    if (existing) {
      existing.source = "AniList + MAL"
      existing.siteUrlMAL = mItem.siteUrl
      if ((mItem.progress || 0) > (existing.progress || 0)) {
        existing.progress = mItem.progress
      }
    } else {
      mItem.source = "MAL"
      combined.push(mItem)
      if (mNorm) map[mNorm] = mItem
      if (mNormRom) map[mNormRom] = mItem
    }
  }

  combined.sort(function(a, b) {
    if (a.status === "RELEASING" && b.status !== "RELEASING") return -1
    if (b.status === "RELEASING" && a.status !== "RELEASING") return 1
    return 0
  })

  return combined
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
    parseMALListResponse: parseMALListResponse,
    parseMALMangaResponse: parseMALMangaResponse,
    parseMALUserAvatar: parseMALUserAvatar,
    normalizeTitle: normalizeTitle,
    mergeAnimeLists: mergeAnimeLists,
    mergeMangaLists: mergeMangaLists,
    parseSearchResponse: parseSearchResponse,
    formatCountdown: formatCountdown,
    formatShortTicker: formatShortTicker,
    formatAiringTime: formatAiringTime,
    formatRelativeTime: formatRelativeTime,
    getTitle: getTitle,
    getCover: getCover
  }
}
