// test/logic.test.mjs - Unit tests for ReleaseLogic.js
import assert from "node:assert/strict"
import test from "node:test"
import { createRequire } from "node:module"

const require = createRequire(import.meta.url)
const Logic = require("../ReleaseLogic.js")

test("buildAniListUserQuery generates valid JSON payload with User avatar", () => {
  const payload = Logic.buildAniListUserQuery("akshad")
  assert.ok(payload)
  const parsed = JSON.parse(payload)
  assert.equal(parsed.variables.userName, "akshad")
  assert.ok(parsed.query.includes("MediaListCollection"))
  assert.ok(parsed.query.includes("User(name: $userName)"))
})

test("buildAniListSearchQuery generates valid search payload", () => {
  const payload = Logic.buildAniListSearchQuery("Solo Leveling")
  assert.ok(payload)
  const parsed = JSON.parse(payload)
  assert.equal(parsed.variables.search, "Solo Leveling")
  assert.ok(parsed.query.includes("Page"))
})

test("formatCountdown handles relative timestamps correctly", () => {
  const now = Math.floor(Date.now() / 1000)

  // Future times (offsets chosen mid-range so ~1s of harness delay can't flip the bucket)
  assert.equal(Logic.formatCountdown(now + 150), "in 2m")
  assert.equal(Logic.formatCountdown(now + 3650), "in 1h")
  assert.equal(Logic.formatCountdown(now + 7290), "in 2h 1m")
  assert.equal(Logic.formatCountdown(now + 91000), "in 1d 1h")
  assert.equal(Logic.formatCountdown(now + 870000), "in 10 days")

  // Past / current time
  assert.equal(Logic.formatCountdown(now - 10), "Just released!")
})

test("parseAniListResponse extracts anime, manga, avatar, and upcoming schedules", () => {
  const mockResponse = {
    data: {
      user: {
        name: "akshad",
        avatar: { large: "https://example.com/avatar.png" }
      },
      anime: {
        lists: [
          {
            name: "Watching",
            status: "CURRENT",
            entries: [
              {
                id: 1,
                progress: 1100,
                score: 10,
                media: {
                  id: 21,
                  title: { romaji: "ONE PIECE", english: "One Piece" },
                  status: "RELEASING",
                  episodes: null,
                  nextAiringEpisode: {
                    id: 1001,
                    episode: 1175,
                    airingAt: Math.floor(Date.now() / 1000) + 7200,
                    timeUntilAiring: 7200
                  },
                  coverImage: { medium: "https://example.com/op.jpg" },
                  siteUrl: "https://anilist.co/anime/21"
                }
              }
            ]
          }
        ]
      },
      manga: { lists: [] }
    }
  }

  const parsed = Logic.parseAniListResponse(mockResponse, {})
  assert.equal(parsed.error, null)
  assert.equal(parsed.userName, "akshad")
  assert.equal(parsed.userAvatar, "https://example.com/avatar.png")
  assert.equal(parsed.watchingAnime.length, 1)
  assert.equal(parsed.watchingAnime[0].title, "One Piece")
  assert.equal(parsed.watchingAnime[0].progress, 1100)
  assert.equal(parsed.upcomingAnime.length, 1)
  assert.equal(parsed.upcomingAnime[0].nextEpisode, 1175)
})

test("parseMALListResponse standardizes MAL anime watchlist", () => {
  const mockMAL = [
    {
      anime_id: 41587,
      anime_title: "Boku no Hero Academia 5th Season",
      anime_title_eng: "My Hero Academia Season 5",
      num_watched_episodes: 11,
      anime_num_episodes: 25,
      anime_airing_status: 2,
      score: 8,
      anime_image_path: "https://example.com/mha.jpg"
    }
  ]

  const list = Logic.parseMALListResponse(mockMAL)
  assert.equal(list.length, 1)
  assert.equal(list[0].title, "My Hero Academia Season 5")
  assert.equal(list[0].progress, 11)
  assert.equal(list[0].totalEpisodes, 25)
  assert.equal(list[0].status, "FINISHED")
  assert.equal(list[0].source, "MAL")
})

test("parseMALMangaResponse standardizes MAL manga watchlist", () => {
  const mockMALManga = [
    {
      manga_id: 14090,
      manga_title: "All Rounder Meguru",
      manga_english: "All Rounder Meguru",
      num_read_chapters: 28,
      manga_num_chapters: 178,
      manga_publishing_status: 2,
      score: 8,
      manga_image_path: "https://example.com/meguru.jpg"
    }
  ]

  const list = Logic.parseMALMangaResponse(mockMALManga)
  assert.equal(list.length, 1)
  assert.equal(list[0].title, "All Rounder Meguru")
  assert.equal(list[0].progress, 28)
  assert.equal(list[0].totalChapters, 178)
  assert.equal(list[0].status, "FINISHED")
  assert.equal(list[0].source, "MAL")
})

test("buildAniListMalEnrichQuery generates valid batch idMal_in payload", () => {
  const payload = Logic.buildAniListMalEnrichQuery([41587, 21])
  assert.ok(payload)
  const parsed = JSON.parse(payload)
  assert.deepEqual(parsed.variables.malIds, [41587, 21])
  assert.ok(parsed.query.includes("idMal_in: $malIds"))
  assert.ok(parsed.query.includes("nextAiringEpisode"))
})

test("parseEnrichResponse maps AniList media by MAL ID", () => {
  const mock = {
    data: {
      Page: {
        media: [
          {
            id: 12345,
            idMal: 41587,
            status: "RELEASING",
            episodes: 25,
            nextAiringEpisode: { episode: 8, airingAt: Math.floor(Date.now() / 1000) + 3600 },
            coverImage: { large: "https://example.com/mha.jpg" },
            siteUrl: "https://anilist.co/anime/12345"
          }
        ]
      }
    }
  }

  const map = Logic.parseEnrichResponse(mock)
  assert.equal(map["41587"].id, 12345)
  assert.equal(map["41587"].nextEpisode, 8)
  assert.equal(map["41587"].airingAt, mock.data.Page.media[0].nextAiringEpisode.airingAt)

  // Errors and garbage produce an empty map, never a throw
  assert.deepEqual(Logic.parseEnrichResponse(null), {})
  assert.deepEqual(Logic.parseEnrichResponse({ errors: [{ message: "oops" }] }), {})
  assert.deepEqual(Logic.parseEnrichResponse("not json"), {})
})

test("applyEnrichment fills MAL entries with airing data and builds upcoming list", () => {
  const now = Math.floor(Date.now() / 1000)
  const malAnime = [
    { mediaId: 41587, title: "My Hero Academia Season 5", progress: 11, status: "FINISHED", siteUrl: "https://myanimelist.net/anime/41587" },
    { mediaId: 21, title: "One Piece", progress: 1100, status: "RELEASING", siteUrl: "https://myanimelist.net/anime/21" }
  ]
  const enrichMap = {
    "21": { id: 21, status: "RELEASING", totalEpisodes: null, nextEpisode: 1175, airingAt: now + 7200, cover: "", siteUrl: "https://anilist.co/anime/21" },
    "41587": { id: 12345, status: "FINISHED", totalEpisodes: 25, nextEpisode: null, airingAt: null, cover: "", siteUrl: "" }
  }

  const res = Logic.applyEnrichment(malAnime, enrichMap)
  const op = res.anime.find(i => i.mediaId === 21)
  assert.equal(op.nextEpisode, 1175)
  assert.equal(op.airingAt, now + 7200)
  assert.equal(op.anilistId, 21)
  assert.equal(res.upcoming.length, 1)
  assert.equal(res.upcoming[0].mediaId, 21)

  // Finished show enriched but not upcoming
  const mha = res.anime.find(i => i.mediaId === 41587)
  assert.equal(mha.totalEpisodes, 25)
  assert.equal(mha.airingAt, null)
})

test("detectDrops fires grouped alerts for MAL-enriched lists across syncs", () => {
  const now = Math.floor(Date.now() / 1000)
  const makeList = (nextEp) => ([
    { mediaId: 21, title: "One Piece", cover: "", siteUrl: "", status: nextEp ? "RELEASING" : "FINISHED", nextEpisode: nextEp }
  ])

  // Baseline sync records state without alerting
  const s1 = Logic.detectDrops(makeList(1170), { seen: {}, lastEp: {}, initialized: false })
  assert.equal(s1.newDrops.length, 0)

  // Offline catch-up: 4 episodes aired at once -> 4 drops
  const s2 = Logic.detectDrops(makeList(1174), s1.updatedTrackerState)
  assert.equal(s2.newDrops.length, 4)
  assert.equal(s2.newDrops[0].title, "One Piece")

  // No change -> no new drops
  const s3 = Logic.detectDrops(makeList(1174), s2.updatedTrackerState)
  assert.equal(s3.newDrops.length, 0)
})

test("parseMALUserAvatar extracts user avatar URL from profile HTML", () => {
  const sampleHtml = `
    <div class="user-image mb8">
      <img class="lazyload" data-src="https://cdn.myanimelist.net/s/common/userimages/c3f4dc4a-ef1f-48d2-970b-cd23a8cc37ad_225w?s=012c053fba954194fcef80b68f1e13c3">
    </div>
  `
  const avatarUrl = Logic.parseMALUserAvatar(sampleHtml)
  assert.equal(avatarUrl, "https://cdn.myanimelist.net/s/common/userimages/c3f4dc4a-ef1f-48d2-970b-cd23a8cc37ad_225w?s=012c053fba954194fcef80b68f1e13c3")
})

test("parseAniListResponse handles non-existent user 404 gracefully", () => {
  const notFound = {
    errors: [{ message: "Not Found.", status: 404 }],
    data: { user: null }
  }
  const res = Logic.parseAniListResponse(notFound, {})
  assert.equal(res.error, "User not found on AniList")
  assert.equal(res.watchingAnime.length, 0)
})

test("parseAniListResponse handles private profile gracefully", () => {
  const privateList = {
    errors: [{ message: "This user's list is private." }],
    data: { user: { name: "secret" } }
  }
  const res = Logic.parseAniListResponse(privateList, {})
  assert.equal(res.error, "AniList profile or list is private")
  assert.equal(res.watchingAnime.length, 0)
})

test("parseMALListResponse handles non-existent and private MAL users gracefully", () => {
  const invalidMal = { errors: [{ message: "invalid request" }] }
  const res1 = Logic.parseMALListResponse(invalidMal)
  assert.equal(res1.error, "User not found on MyAnimeList")

  const privateMal = { errors: [{ message: "list is private" }] }
  const res2 = Logic.parseMALListResponse(privateMal)
  assert.equal(res2.error, "MAL watchlist is private")
})

// ----------------------------------------------------------- Simkl

test("buildSimklPinStartUrl and buildSimklPinPollUrl carry required app params", () => {
  const startUrl = Logic.buildSimklPinStartUrl("abc123")
  assert.ok(startUrl.startsWith("https://api.simkl.com/oauth/pin?"))
  assert.ok(startUrl.includes("client_id=abc123"))
  assert.ok(startUrl.includes("app-name=anisync"))
  assert.ok(startUrl.includes("app-version="))

  const pollUrl = Logic.buildSimklPinPollUrl("ABCDE", "abc123")
  assert.ok(pollUrl.startsWith("https://api.simkl.com/oauth/pin/ABCDE?"))
  assert.ok(pollUrl.includes("client_id=abc123"))
})

test("parseSimklPinStart extracts user code and polling cadence", () => {
  const res = Logic.parseSimklPinStart(JSON.stringify({
    result: "OK",
    user_code: "ABCDE",
    verification_uri: "https://simkl.com/pin",
    expires_in: 900,
    interval: 5
  }))
  assert.equal(res.ok, true)
  assert.equal(res.userCode, "ABCDE")
  assert.equal(res.verificationUrl, "https://simkl.com/pin")
  assert.equal(res.pollIntervalSecs, 5)

  // Failures never throw
  assert.equal(Logic.parseSimklPinStart(null).ok, false)
  assert.equal(Logic.parseSimklPinStart("not json").ok, false)
  assert.equal(Logic.parseSimklPinStart("{}").ok, false)
  assert.ok(Logic.parseSimklPinStart(null).error)
})

test("parseSimklPinPoll walks pending -> authorized -> expired states", () => {
  const pending = Logic.parseSimklPinPoll('{"result":"KO","message":"Authorization pending"}')
  assert.equal(pending.state, "pending")
  assert.equal(pending.accessToken, "")

  const authorized = Logic.parseSimklPinPoll('{"result":"OK","access_token":"tok_123"}')
  assert.equal(authorized.state, "authorized")
  assert.equal(authorized.accessToken, "tok_123")

  // device_code in a poll reply means the original code is gone
  const expired = Logic.parseSimklPinPoll('{"result":"OK","device_code":"DEVICE_CODE","user_code":"ZZZZZ"}')
  assert.equal(expired.state, "expired")

  // Empty body / garbage stay pending (harmless retry next tick)
  assert.equal(Logic.parseSimklPinPoll("").state, "pending")
  assert.equal(Logic.parseSimklPinPoll("garbage").state, "pending")
})

test("parseSimklUserProfile reads name, avatar, and plan type", () => {
  const profile = Logic.parseSimklUserProfile(JSON.stringify({
    user: { name: "akshad", avatar: "https://simkl.in/avatars/x.jpg" },
    account: { id: 1, type: "free" }
  }))
  assert.equal(profile.userName, "akshad")
  assert.equal(profile.avatar, "https://simkl.in/avatars/x.jpg")
  assert.equal(profile.accountType, "free")

  const bad = Logic.parseSimklUserProfile('{"error":true}')
  assert.equal(bad.error, "Could not read Simkl profile")
  assert.equal(Logic.parseSimklUserProfile(null).error, "No response from Simkl")
})

test("buildSimklListUrl targets anime and shows watching endpoints", () => {
  const animeUrl = Logic.buildSimklListUrl("anime", "abc123")
  assert.ok(animeUrl.startsWith("https://api.simkl.com/sync/all-items/anime/watching?"))
  assert.ok(animeUrl.includes("next_watch_info=yes"))
  assert.ok(animeUrl.includes("client_id=abc123"))

  const showsUrl = Logic.buildSimklListUrl("shows", "abc123")
  assert.ok(showsUrl.startsWith("https://api.simkl.com/sync/all-items/shows/watching?"))

  const tvCal = Logic.buildSimklTvCalendarUrl()
  assert.equal(tvCal, "https://data.simkl.in/calendar/tv.json")
})

test("parseSimklCalendar flattens CDN rows into simkl and mal keyed schedules", () => {
  const cal = Logic.parseSimklCalendar(JSON.stringify([
    {
      title: "One Piece",
      date: "2026-08-23T02:30:00+09:00",
      url: "https://simkl.com/anime/1/op/episode-1175/",
      ids: { simkl_id: 1, mal: 21 },
      episode: { episode: 1175 }
    },
    { date: null }, // malformed rows are skipped silently
    { date: "2026-08-24T00:00:00+09:00", episode: {} }
  ]))

  assert.ok(cal["s1"])
  assert.equal(cal["s1"].episode, 1175)
  assert.equal(typeof cal["s1"].airingAt, "number")
  assert.deepEqual(cal["m21"], cal["s1"])

  // Garbage input yields an empty map, never a throw
  assert.deepEqual(Logic.parseSimklCalendar(null), {})
  assert.deepEqual(Logic.parseSimklCalendar("nope"), {})
})

test("simklPosterUrl builds absolute poster URLs and falls back to placeholder", () => {
  assert.equal(
    Logic.simklPosterUrl("74/74415673dcdc9cdd"),
    "https://simkl.in/posters/74/74415673dcdc9cdd_w.webp"
  )
  assert.equal(
    Logic.simklPosterUrl(""),
    "https://simkl.in/poster_no_pic_c.png"
  )
})

test("parseSimklResponse standardizes watching list and joins calendar airing times", () => {
  const now = Math.floor(Date.now() / 1000)
  const airingIn2h = now + 7200
  const mock = {
    anime: [
      {
        status: "watching",
        watched_episodes_count: 1100,
        total_episodes_count: null,
        not_aired_episodes_count: 3,
        user_rating: 10,
        next_to_watch_info: { title: "ONE PIECE", season: 1, episode: 1174, date: null },
        anime: {
          title: "ONE PIECE",
          poster: "74/74415673dcdc9cdd",
          ids: { simkl: 1, mal: "21", anilist: "20958" }
        }
      },
      {
        status: "watching",
        watched_episodes_count: 4,
        total_episodes_count: 12,
        not_aired_episodes_count: 8,
        anime: {
          title: "Fragrant Air Season 2",
          poster: "",
          ids: { simkl: 2, mal: null }
        },
        next_to_watch_info: { episode: 5, date: new Date((now + 3600) * 1000).toISOString() }
      }
    ]
  }

  const calendarMap = {
    s1: { episode: 1175, airingAt: airingIn2h, siteUrl: "https://simkl.com/anime/1/op/episode-1175/" }
  }

  const parsed = Logic.parseSimklResponse(mock, {}, calendarMap)
  assert.equal(parsed.error, null)
  assert.equal(parsed.watchingAnime.length, 2)

  const op = parsed.watchingAnime.find(i => i.mediaId === 1)
  assert.equal(op.title, "ONE PIECE")
  assert.equal(op.mediaId, 1)
  assert.equal(op.progress, 1100)
  assert.equal(op.status, "RELEASING")
  assert.equal(op.source, "SIMKL")
  assert.equal(op.malId, 21)
  assert.equal(op.anilistId, 20958)
  assert.equal(op.cover, "https://simkl.in/posters/74/74415673dcdc9cdd_w.webp")
  // Calendar join wins over the entry's own info; site URL upgraded to the episode link
  assert.equal(op.nextEpisode, 1175)
  assert.equal(op.airingAt, airingIn2h)
  assert.equal(op.siteUrl, "https://simkl.com/anime/1/op/episode-1175/")
  assert.equal(parsed.upcomingAnime.length, 2)
  assert.equal(parsed.upcomingAnime[0].mediaId, 2) // airs sooner, sorted first

  // Manga never exists on Simkl
  assert.equal(parsed.readingManga.length, 0)
})

test("parseSimklResponse marks finished shows for finale detection via detectDrops", () => {
  const showId = 555
  const makePayload = () => ({
    anime: [
      {
        status: "watching",
        watched_episodes_count: 13,
        total_episodes_count: 14,
        not_aired_episodes_count: 0,
        anime: { title: "Ending Show", ids: { simkl: showId } }
      }
    ]
  })

  // Baseline: ep 14 upcoming records state without alerting
  const withUpcoming = makePayload()
  withUpcoming.anime[0].not_aired_episodes_count = 1
  const calendarMap = { ["s" + showId]: { episode: 14, airingAt: Math.floor(Date.now() / 1000) + 3600 } }
  const sync1 = Logic.parseSimklResponse(withUpcoming, { seen: {}, lastEp: {}, initialized: false }, calendarMap)
  assert.equal(sync1.newDrops.length, 0)
  assert.equal(sync1.updatedTrackerState.lastEp[showId], 14)

  // Finale aired: calendar no longer lists it, status flips to FINISHED,
  // detectDrops catches up the missed episode exactly once
  const afterFinale = makePayload()
  const sync2 = Logic.parseSimklResponse(afterFinale, sync1.updatedTrackerState, {})
  assert.equal(sync2.newDrops.length, 1)
  assert.equal(sync2.newDrops[0].episode, 14)
})

test("parseSimklResponse handles empty list and invalid payloads gracefully", () => {
  const empty = Logic.parseSimklResponse({ anime: [] }, {})
  assert.equal(empty.error, null)
  assert.equal(empty.watchingAnime.length, 0)

  assert.equal(Logic.parseSimklResponse(null, {}).error, "No response from Simkl")
  assert.equal(Logic.parseSimklResponse("garbage", {}).error, "Invalid Simkl response format")
})

test("parseAniListResponse only includes CURRENT watching anime and CURRENT reading manga", () => {
  const mock = {
    data: {
      user: { name: "testuser" },
      anime: {
        lists: [
          {
            name: "Watching",
            status: "CURRENT",
            entries: [
              {
                id: 1,
                progress: 5,
                media: {
                  id: 101,
                  title: { english: "Watching Show" },
                  nextAiringEpisode: { episode: 6, airingAt: Math.floor(Date.now() / 1000) + 3600 }
                }
              }
            ]
          },
          {
            name: "Planning",
            status: "PLANNING",
            entries: [
              {
                id: 2,
                progress: 0,
                media: {
                  id: 102,
                  title: { english: "Planning Show" },
                  nextAiringEpisode: { episode: 1, airingAt: Math.floor(Date.now() / 1000) + 1800 }
                }
              }
            ]
          }
        ]
      },
      manga: {
        lists: [
          {
            name: "Reading",
            status: "CURRENT",
            entries: [{ id: 3, progress: 10, media: { id: 201, title: { english: "Reading Manga" } } }]
          },
          {
            name: "Planning",
            status: "PLANNING",
            entries: [{ id: 4, progress: 0, media: { id: 202, title: { english: "Planning Manga" } } }]
          }
        ]
      }
    }
  }

  const parsed = Logic.parseAniListResponse(mock, {})
  assert.equal(parsed.watchingAnime.length, 1)
  assert.equal(parsed.watchingAnime[0].title, "Watching Show")
  assert.equal(parsed.upcomingAnime.length, 1)
  assert.equal(parsed.upcomingAnime[0].title, "Watching Show")
  assert.equal(parsed.readingManga.length, 1)
  assert.equal(parsed.readingManga[0].title, "Reading Manga")
})

test("state transition detects newly aired episodes across syncs and offline periods", () => {
  const showId = 135865
  const createPayload = (nextEp, airingAt) => ({
    data: {
      user: { name: "testuser" },
      anime: {
        lists: [
          {
            name: "Watching",
            status: "CURRENT",
            entries: [
              {
                id: 1,
                progress: 6,
                media: {
                  id: showId,
                  title: { english: "Saga of Tanya the Evil Season 2" },
                  nextAiringEpisode: nextEp ? { episode: nextEp, airingAt: airingAt || Math.floor(Date.now() / 1000) + 3600 } : null,
                  status: nextEp ? "RELEASING" : "FINISHED"
                }
              }
            ]
          }
        ]
      },
      manga: { lists: [] }
    }
  })

  // 1. Initial Sync: Ep 7 is coming up. Records state without firing alerts.
  const sync1 = Logic.parseAniListResponse(createPayload(7), { seen: {}, lastEp: {}, initialized: false })
  assert.equal(sync1.newDrops.length, 0)
  assert.equal(sync1.updatedTrackerState.lastEp[showId], 7)

  // 2. Later Sync (e.g. after sleep/reboot): Ep 7 aired, now Ep 8 is upcoming!
  const sync2 = Logic.parseAniListResponse(createPayload(8), sync1.updatedTrackerState)
  assert.equal(sync2.newDrops.length, 1)
  assert.equal(sync2.newDrops[0].episode, 7)
  assert.equal(sync2.newDrops[0].title, "Saga of Tanya the Evil Season 2")
  assert.equal(sync2.updatedTrackerState.lastEp[showId], 8)

  // 3. Re-sync without changes: No new alerts.
  const sync3 = Logic.parseAniListResponse(createPayload(8), sync2.updatedTrackerState)
  assert.equal(sync3.newDrops.length, 0)

  // 4. Series Finale Sync: Ep 12 aired, show finished.
  const syncFinale = Logic.parseAniListResponse(createPayload(null), { seen: {}, lastEp: { [showId]: 12 }, initialized: true })
  assert.equal(syncFinale.newDrops.length, 1)
  assert.equal(syncFinale.newDrops[0].episode, 12)
})

test("finale after multi-week gap catches up every missed episode up to the total", () => {
  const showId = 999
  const payload = {
    data: {
      user: { name: "testuser" },
      anime: {
        lists: [
          {
            name: "Watching",
            status: "CURRENT",
            entries: [
              {
                id: 1,
                progress: 12,
                media: {
                  id: showId,
                  title: { english: "Finished Show" },
                  status: "FINISHED",
                  episodes: 14,
                  nextAiringEpisode: null
                }
              }
            ]
          }
        ]
      },
      manga: { lists: [] }
    }
  }

  // Last seen next-episode was 13; eps 13 and 14 aired while offline
  const res = Logic.parseAniListResponse(payload, { seen: {}, lastEp: { [showId]: 13 }, initialized: true })
  assert.equal(res.newDrops.length, 2)
  assert.deepEqual(res.newDrops.map(d => d.episode).sort(), [13, 14])

  // Unknown total degrades to previous behavior (only prevEp alerted)
  const noTotal = JSON.parse(JSON.stringify(payload))
  delete noTotal.data.anime.lists[0].entries[0].media.episodes
  const res2 = Logic.parseAniListResponse(noTotal, { seen: {}, lastEp: { [showId]: 13 }, initialized: true })
  assert.equal(res2.newDrops.length, 1)
  assert.equal(res2.newDrops[0].episode, 13)
})

test("upcomingList is strictly sorted by closest chronological airing time across all anime", () => {
  const now = Math.floor(Date.now() / 1000)
  const mockMulti = {
    data: {
      user: { name: "testuser" },
      anime: {
        lists: [
          {
            name: "Watching",
            status: "CURRENT",
            entries: [
              {
                id: 1,
                media: {
                  id: 101,
                  title: { english: "Show C (airs in 6 days)" },
                  nextAiringEpisode: { episode: 8, airingAt: now + 518400 }
                }
              },
              {
                id: 2,
                media: {
                  id: 102,
                  title: { english: "Show A (airs in 1 day)" },
                  nextAiringEpisode: { episode: 9, airingAt: now + 86400 }
                }
              },
              {
                id: 3,
                media: {
                  id: 103,
                  title: { english: "Show B (airs in 3 days)" },
                  nextAiringEpisode: { episode: 21, airingAt: now + 259200 }
                }
              }
            ]
          }
        ]
      },
      manga: { lists: [] }
    }
  }

  const parsed = Logic.parseAniListResponse(mockMulti, {})
  assert.equal(parsed.upcomingAnime.length, 3)
  assert.equal(parsed.upcomingAnime[0].title, "Show A (airs in 1 day)")
  assert.equal(parsed.upcomingAnime[1].title, "Show B (airs in 3 days)")
  assert.equal(parsed.upcomingAnime[2].title, "Show C (airs in 6 days)")
  assert.equal(Logic.formatShortTicker(parsed.upcomingAnime[0]).includes("Show A"), true)
})

test("cache automatically prunes shows when moved out of CURRENT (completed/paused/dropped)", () => {
  const show1 = 101
  const show2 = 102

  // Initial state tracking 2 shows
  const tracker = {
    seen: { [`${show1}:7`]: 1700000000, [`${show2}:3`]: 1700000000 },
    lastEp: { [show1]: 8, [show2]: 4 },
    initialized: true
  }

  // Next sync: user completed / dropped show2, so CURRENT only has show1
  const payloadOnlyShow1 = {
    data: {
      user: { name: "testuser" },
      anime: {
        lists: [
          {
            name: "Watching",
            status: "CURRENT",
            entries: [
              {
                id: 1,
                media: {
                  id: show1,
                  title: { english: "Show 1 Still Watching" },
                  nextAiringEpisode: { episode: 8, airingAt: Math.floor(Date.now() / 1000) + 3600 }
                }
              }
            ]
          }
        ]
      },
      manga: { lists: [] }
    }
  }

  const parsed = Logic.parseAniListResponse(payloadOnlyShow1, tracker)

  // Show 1 is kept in lastEp and seen
  assert.equal(parsed.updatedTrackerState.lastEp[show1], 8)
  assert.ok(parsed.updatedTrackerState.seen[`${show1}:7`])

  // Show 2 is completely removed/pruned from lastEp and seen cache
  assert.equal(parsed.updatedTrackerState.lastEp[show2], undefined)
  assert.equal(parsed.updatedTrackerState.seen[`${show2}:3`], undefined)
})



