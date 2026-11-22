--!strict
--[[
	Per-biome tuning (GDD §9 biome table). Base Boss HP is derived so a solo fighter at the
	portal's Recommended Damage finishes the boss in ~52s (GDD: "smooth 45–60s fight").
]]

export type BiomeConfig = {
	biomeId: string,
	bossId: string,
	recommendedDamage: number,
	baseBossHp: number,
	pveDamageMultiplier: number, -- GDD §6: PvE mob kills grant 1.5x–6x Ball DMG by biome tier
	mobKinds: { string },
}

local BiomeConfigs = {}

BiomeConfigs.SOLO_FIGHT_SECONDS = 52
-- 0.35s throw cooldown at ~70% boss uptime ~= 2 accepted throws/s (Gemini #5 plan §3.3).
BiomeConfigs.THROWS_PER_SECOND = 2

local function make(
	biomeId: string,
	bossId: string,
	recommendedDamage: number,
	pveDamageMultiplier: number,
	mobKinds: { string }
): BiomeConfig
	return table.freeze({
		biomeId = biomeId,
		bossId = bossId,
		recommendedDamage = recommendedDamage,
		pveDamageMultiplier = pveDamageMultiplier,
		mobKinds = table.freeze(mobKinds),
		baseBossHp = recommendedDamage
			* BiomeConfigs.THROWS_PER_SECOND
			* BiomeConfigs.SOLO_FIGHT_SECONDS,
	})
end

BiomeConfigs.Biomes = table.freeze({
	EmeraldMeadow = make("EmeraldMeadow", "MossbackGolem", 15, 1.5, { "MossSlime", "BrambleBoar" }),
	-- Biome 2-3 mobs arrive with #17.
	FrostbiteCavern = make("FrostbiteCavern", "GlacierYeti", 150, 3.0, {}),
	MoltenCaldera = make("MoltenCaldera", "ObsidianWyrm", 1200, 6.0, {}),
})

function BiomeConfigs.get(biomeId: string): BiomeConfig?
	return BiomeConfigs.Biomes[biomeId]
end

return BiomeConfigs
