# Player Group

<!-- from github.com/Roblox/libmp/docs/ALL-SCOPES.md -->
The Player group contains scopes for player character loading: rig construction, appearance application, avatar asset loading, and script installation. These scopes fire when a player joins or respawns.

---

## Character Loading Pipeline

### loadCharacterRig

**Loads the character rig (R6 or R15 skeleton) — creates the body part hierarchy and Motor6D joints.**

Constructs the base character model with all body parts, HumanoidRootPart, and joint connections. This is the structural foundation before appearance is applied.

**Performance notes:** One-time cost per spawn. Typically fast (structural assembly from templates).


---

### loadCharacterModel

**Assembles the base character model — loads the rig, sets up the Humanoid, and installs character scripts.**

Loads the character rig (via loadCharacterRig), replaces/initializes the Humanoid, and installs character scripts. It does not apply mesh appearance, body colors, or accessories — those are handled separately by applyCharacterAppearanceAssets.


---

### loadCharacterAppearanceAssets / applyCharacterAppearanceAssets

**Loads and applies appearance assets (clothing, body parts, face) to the character.**

Downloads and applies all avatar appearance items: shirts, pants, body colors, faces, and custom body parts.

**Performance notes:** Can be slow if many assets need downloading. First spawn is slower due to asset cache misses.


---

### applyAppearanceAsset

**Applies a single appearance asset to the character (one clothing item or body part).**


---

### loadCharacterScripts / loadHumanoidAnimationScripts

**Installs the Animate script and other character scripts onto the spawned character.**

Adds the default Animate script (controls idle, walk, run, jump animations) and Health script to the character.

**Performance notes:** Negligible.


---

### destroyMotor6Ds

**Destroys Motor6D joints during character teardown or rig swap.**


---

### handleAvatarFetchResponse

**Processes the avatar fetch API response — parses appearance data from the backend.**

Handles the HTTP response containing the player's avatar configuration (equipped items, body colors, etc.).


---

## Player Management

### ParentPlayer

**Parents a Player instance into the Players service — the core player installation step.**

Called when a player's connection is accepted. Parents the already-created Player instance into the Players service, making the player visible to the game.

**Performance notes:** Triggers cascading work (scripts fire PlayerAdded, character loading begins).


---

### RemovePlayer

**Removes a Player instance from the game — handles disconnection cleanup.**

Called on disconnect. Un-parents the Player instance, which triggers cascading cleanup of the character, backpack, and associated state.

**Performance notes:** Can trigger cascading cleanup (scripts fire PlayerRemoving, character destroyed).


<br>
<br>

---
