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
}

local BiomeConfigs = {}

BiomeConfigs.SOLO_FIGHT_SECONDS = 52
-- shortcut: assumes 1 accepted throw/s; re-derive when CombatService fixes the throw cooldown.
BiomeConfigs.THROWS_PER_SECOND = 1

local function make(biomeId: string, bossId: string, recommendedDamage: number): BiomeConfig
	return table.freeze({
		biomeId = biomeId,
		bossId = bossId,
		recommendedDamage = recommendedDamage,
		baseBossHp = recommendedDamage
			* BiomeConfigs.THROWS_PER_SECOND
			* BiomeConfigs.SOLO_FIGHT_SECONDS,
	})
end

BiomeConfigs.Biomes = table.freeze({
	EmeraldMeadow = make("EmeraldMeadow", "MossbackGolem", 15),
	FrostbiteCavern = make("FrostbiteCavern", "GlacierYeti", 150),
	MoltenCaldera = make("MoltenCaldera", "ObsidianWyrm", 1200),
})

function BiomeConfigs.get(biomeId: string): BiomeConfig?
	return BiomeConfigs.Biomes[biomeId]
end

return BiomeConfigs
