// test/logic.test.mjs - Unit tests for ReleaseLogic.js
import assert from "node:assert/strict"
import test from "node:test"
import { createRequire } from "node:module"

const require = createRequire(import.meta.url)
const Logic = require("../ReleaseLogic.js")

test("buildAniListUserQuery generates valid JSON payload", () => {
  const payload = Logic.buildAniListUserQuery("akshad")
  assert.ok(payload)
  const parsed = JSON.parse(payload)
  assert.equal(parsed.variables.userName, "akshad")
  assert.ok(parsed.query.includes("MediaListCollection"))
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

test("parseAniListResponse extracts anime and upcoming schedules", () => {
  const mockResponse = {
    data: {
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
  assert.equal(parsed.watchingAnime.length, 1)
  assert.equal(parsed.watchingAnime[0].title, "One Piece")
  assert.equal(parsed.watchingAnime[0].progress, 1100)
  assert.equal(parsed.upcomingAnime.length, 1)
  assert.equal(parsed.upcomingAnime[0].nextEpisode, 1175)
})

test("parseMALListResponse standardizes MAL watchlist", () => {
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
})
