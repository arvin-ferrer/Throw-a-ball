# Ball Brawl: Boss Eggs — 3D Art Direction & Style Guide (`STYLE_GUIDE.md`)

**Visual North Star:** `game/assets/renders/Pyraxis_live_preview.png` (lofted low-poly organic silhouettes, beveled layered armor plates, curved tapered horns/claws/spines, controlled 3-tier color hierarchy, dark neutral studio preview lighting) fused with mobile-first readability principles from top Roblox pet/simulator titles (*Pet Simulator 99*, *Adopt Me!*, *Bee Swarm Simulator* — style reference only, zero copied designs or branding).

---

## 1. Core Visual DNA (One Unified Style Across All Assets)

1. **Sculpted Stylized Low-Poly (No Bare Primitives):**
   - Organic forms (bodies, limbs, snouts, ears, tails, curved tusks, antlers, vines, sprouts) use **multi-ring lofted tubes (`add_lofted_tube`)** or **smooth lathe shells (`add_lathe_shell`)** — never unshaped raw cubes or pinched spheres.
   - Hard-surface & mineral forms (stone armor plates, moss clumps, crystals, forged metal bands, gold prize trim) use **beveled flat-faceted geometry** (`smooth = False`) so highlights catch crisp planar facets just like Pyraxis.
   - Blend smooth shading (`smooth = True`) on squishy/plush/organic bodies (pets, slimes, boars, prize egg shell) with flat shading (`smooth = False`) on crystals, stone armor, claws, horns, and metal hardware.
2. **Mobile-First Silhouette & Proportions (`128×128` Squint Rule):**
   - **Pets (`TrainingPup`, `PebbleCub`, `DewSprite`, `ThornStag`, `GolemHeart`):** Heroic chibi-toy proportions — oversized head/focal core (`45%–55%` of total silhouette volume), amplified defining features (floppy ears, curved antlers, wide leaf wings, orbiting rune gauntlets), stubby grounded paws or floating mythic aura, and large high-contrast glossy eyes (`Roughness 0.08`) with bright white specular catchlights so personality reads even in tiny inventory thumbnails.
   - **PvE Mobs (`MossSlime`, `BrambleBoar`):** Compact, chunky, silhouette-distinct at 40–70 studs (`3.4–4.2` studs tall) with bright crown/dorsal accents so they pop cleanly against meadow grass.
   - **Bosses (`MossbackGolem`, `Pyraxis`):** Towering `12+` stud silhouettes (~2.2× a 5.5-stud Roblox avatar) with bold shoulder/dorsal framing and unmistakable attack-telegraph poses.
   - **Prize Eggs & Ball Tiers:** Escalate rarity/tier through **3D silhouette hardware** (gold chalice rims, inlaid gems, crystal crowns, riveted iron hoops, ice spikes, obsidian armor plates, orbital gyro rings) — never bare recolored spheres.

---

## 2. Color Palette, Saturation Hierarchy & PBR Shading Rules

Follow a **controlled 3-tier saturation hierarchy** (preventing eye fatigue during long sessions while making rewards, pets, and combat telegraphs pop on phones):

| Layer | Saturation / Value | Roughness | Metallic | Examples |
| :--- | :--- | :---: | :---: | :--- |
| **1. Grounded Structural Base** | Low–Medium saturation (`20%–45%`), deep grounded value | `0.60–0.88` (matte stone, bark, fur) | `0.0` | Dark slate `#242926`, weathered stone `#4A524C`, woodland bark `#4B3629`, obsidian `#191417` |
| **2. Midtone Body & Armor** | Medium–High saturation (`45%–70%`), clean readable value | `0.22–0.55` (glossy pet enamel, plush fur, gelatin) | `0.0` (or `0.85–0.95` strictly for metals!) | Warm honey-tan `#D99B52`, lush moss `#257A36`, glacier blue `#268CE0`, brushed gold `#F8C43D`, ivory `#E6DEC8` |
| **3. Focal Accents & Emissives** | High saturation (`80%–100%`), bright value | `0.10–0.22` | `0.0` | Jade rune crystal `#1AE870`, molten ember `#FF4608`, starlight cyan `#4CEBFF`, glossy eye catchlights `#FFFFFF` |

### Strict PBR & Emissive Guardrails
- **Binary Metalness:** Keep `Metallic` near `0.0` for organic/stone/gel materials and `0.82–0.95` strictly for true metals (gold rings, forged steel, rivets). Avoid muddy mid-range metalness (`0.3–0.6`) except subtle cosmic enamel.
- **Controlled Emissive Strength (`1.6–2.8` in Cycles/Studio):** Never crank emission above `3.5` on colored crystals/lava, or colors wash out to pure white. Keep emissive accents to `<= 15%` of surface area so the dark/midtone silhouette remains crisp.
- **Studio Preview Lighting Standard:** Always render previews in colored PBR (`CYCLES` CPU `20–24` samples on `#2E3238` dark neutral studio backdrop with 3-point key/fill/rim area lights + subtle matte studio floor). Never use clay-grey `BLENDER_WORKBENCH`.

---

## 3. Technical Export & Triangle Budgets (Roblox Mobile 60 FPS)

- **Scale & Orientation:** `1 Blender unit = 1 Roblox stud`, built facing `-Y` (`+Z` up) in Blender → exported `-Z` forward, `+Y` up in both `.fbx` and `.glb`.
- **Pivots:** Floor center `(0, 0, 0)` (`min_z ≈ 0.00`) for Bosses, Mobs, Eggs, and Grounded Pets; geometric center `(0, 0, 0)` for Balls, Boulders, and floating center-bobbing Pets (with `min_z >= 0.0` for floating pedestal pets so they hover cleanly above a pedestal!).
- **Rigging:** Root bone `HumanoidRootPart` for Bosses/Mobs (`Root` for Pets/Eggs/Balls per Contract B), `<= 4` bone weights/vert, zero unweighted vertices, 24 FPS NLA tracks.

| Asset Class | Target Triangles | Hard Cap | PrimaryPart |
| :--- | :---: | :---: | :--- |
| **Biome Bosses** | `2,000–5,500` | `< 6,000` *(Roblox max 10k)* | `HumanoidRootPart` |
| **PvE Mobs** | `800–2,200` | `< 2,500` | `HumanoidRootPart` |
| **Boss / Prize Eggs** | `1,000–2,000` | `< 2,500` | `Root` |
| **Unified Pets (Hub + Followers)** | `900–2,000` | `< 2,500` | `Root` |
| **Throwable Balls & Projectiles** | `300–900` | `< 1,200` | `Root` |

---

## 4. Audit of Existing Issue #8 Assets Against This Style Guide

| Existing Asset | Audit Status | Notes Against `STYLE_GUIDE.md` |
| :--- | :---: | :--- |
| `MossbackGolem` (`2,052` tris) | **PASS** | Strong 12.5-stud silhouette, Chest-anchored pauldrons, controlled `2.4` jade glow, clean 16-bone rig & 5 NLA clips, grounded `min_z = 0.00`. Slightly architectural/blocky chest fits ancient carved stone; future optional pass could soften upper limbs. |
| `MossbackBoulder` (`336` tris) | **PASS** | Crisp faceted basalt, two-tone moss rotation cues, glowing jade shards, exact 6.5-stud scale. |
| `RubberBall` (`440` tris) | **PASS** | Seamless cream athletic seams, vibrant crimson satin finish, `1.10` studs. |
| `IronSphere` (`688` tris) | **PASS** | True binary-metallic forged steel hoops & octagonal rivets, `1.19` studs. |
| `FrostOrb` (`336` tris) | **PASS** | Outward-pointing crystal spikes + controlled `1.7` glacier halo, `1.34` studs. |
| `MagmaCore` (`480` tris) | **PASS** | Beveled dark obsidian armor plates framing glowing `2.6` molten fissures (directly echoes Pyraxis), `1.33` studs. |
| `NovaSphere` (`584` tris) | **PASS** | Seamless metallic gold dual gyro rings + cosmic violet core + cyan starlight nodes, `1.45` studs. |
| Old `BossEgg_Meadow` (`starter_egg_template.py`) | **FAIL — REPLACED** | Clay-grey Workbench render + pinched equator + zero prize details; replaced by `boss_egg_meadow.py`. |
