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
