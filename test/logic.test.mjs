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
  
  // Future times
  assert.equal(Logic.formatCountdown(now + 120), "in 2m")
  assert.equal(Logic.formatCountdown(now + 3600), "in 1h")
  assert.equal(Logic.formatCountdown(now + 7300), "in 2h 1m")
  assert.equal(Logic.formatCountdown(now + 90000), "in 1d 1h")
  assert.equal(Logic.formatCountdown(now + 864000), "in 10 days")

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

test("mergeAnimeLists cleanly unifies and deduplicates AniList + MAL anime lists", () => {
  const aniListAnime = [
    {
      id: "al_21",
      title: "One Piece",
      romaji: "ONE PIECE",
      english: "One Piece",
      progress: 1100,
      status: "RELEASING",
      airingAt: Math.floor(Date.now() / 1000) + 3600,
      nextEpisode: 1175
    }
  ]

  const malAnime = [
    // Duplicate title with higher progress on MAL
    {
      id: "mal_21",
      title: "One Piece",
      progress: 1105,
      status: "RELEASING",
      siteUrl: "https://myanimelist.net/anime/21/One_Piece"
    },
    // Distinct MAL-only show
    {
      id: "mal_790",
      title: "Ergo Proxy",
      progress: 5,
      status: "FINISHED",
      siteUrl: "https://myanimelist.net/anime/790/Ergo_Proxy"
    }
  ]

  const unified = Logic.mergeAnimeLists(aniListAnime, malAnime)
  assert.equal(unified.length, 2)
  
  // One Piece deduplicated with synced higher progress from MAL
  const op = unified.find(i => i.title === "One Piece")
  assert.ok(op)
  assert.equal(op.progress, 1105)
  assert.equal(op.source, "AniList + MAL")
  assert.equal(op.nextEpisode, 1175)

  // Ergo Proxy included from MAL
  const ergo = unified.find(i => i.title === "Ergo Proxy")
  assert.ok(ergo)
  assert.equal(ergo.source, "MAL")
})

test("mergeMangaLists cleanly unifies AniList + MAL manga reading lists", () => {
  const aniListManga = [
    {
      id: "al_m_1",
      title: "Chainsaw Man",
      progress: 150,
      status: "RELEASING"
    }
  ]

  const malManga = [
    {
      id: "mal_m_2",
      title: "Berserk",
      progress: 370,
      status: "RELEASING"
    }
  ]

  const unified = Logic.mergeMangaLists(aniListManga, malManga)
  assert.equal(unified.length, 2)
  assert.ok(unified.find(m => m.title === "Chainsaw Man"))
  assert.ok(unified.find(m => m.title === "Berserk"))
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



