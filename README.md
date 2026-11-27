# EditTime

EditTime fills in the gaps in Blizzard's Edit Mode for WoW Forever. Every option lives inside Edit Mode itself:
select a frame and EditTime's settings appear in a panel attached to Blizzard's settings window, styled to match.
Settings are saved per Edit Mode layout, so each layout keeps its own setup.

## Features

### Match Width and Match Height

Size a frame to the width or height of any other Edit Mode frame. For example, you can make an unlocked cast bar
exactly as wide as your Essential Cooldowns, or make a vertical micro menu as tall as the minimap. The match keeps
up as the other frame changes size, and anything that changes during combat is applied when combat ends.

| Frame                     | Width | Height | Notes                                                   |
|---------------------------|:-----:|:------:|---------------------------------------------------------|
| Cast Bar                  | Yes   |        | Unlock it from the Player Frame and move it first       |
| Personal Resource Display | Yes   |        | Health, power and class resource bars all stretch       |
| Experience and Status bars| Yes   |        | Move the bar away from its default position first       |
| Swing Timer bars          | Yes   | Yes    | Move the bar away from its default position first       |
| Damage Meter              | Yes   | Yes    | Replaces its own width and height settings while matched|
| Chat Frame                | Yes   | Yes    | Replaces its own width and height settings while matched|
| Bags                      | Yes   | Yes    | Scales as a whole, so pick width or height              |
| Micro Menu                | Yes   | Yes    | Scales as a whole, so pick width or height              |

Blizzard only gives the Cast Bar a Bar Size setting, which scales the whole bar. Once the Cast Bar is unlocked
from the Player Frame and moved, EditTime adds a **Bar Width** slider so you can make it wider (or narrower)
without changing its height. Match Width takes over while it's set.

Bags and the Micro Menu scale evenly so the buttons keep their shape. Since a single scale can only fit one
target, choosing a width match clears the height match and vice versa. Any Edit Mode frame can be the one you
match to, including Cooldown Viewer groups, action bars and unit frames.

### Visibility

Choose Always, In Combat, Out of Combat or Hidden for the Minimap, Objective Tracker, Experience and Reputation
bars, Bags and Micro Menu. Everything shows while Edit Mode is open. In vehicles and pet battles the Micro Menu
moves onto Blizzard's vehicle bar and stays usable there.

### Party and Raid Frames

**Growth** (Raid Frames). Pick a horizontal direction (Right, Center or Left) and a vertical one (Down, Center or
Up). The frames sit where you placed them in Edit Mode and grow or shrink around that point as people join and
leave, so a centered healing layout stays centered.

**Hide Own Frame** (Raid Frames and raid style Party Frames). Removes your own frame and closes the gap it leaves.
If Blizzard redraws the frames during combat, for example when someone leaves the group, your frame may come back
until combat ends. EditTime never hides or covers anyone else's frame.

**Hide Party Title** removes the "Party" label above the raid style Party Frames.

**Hide DPS Role Icons** removes the role icon from damage dealers.

**Only Tank and Healer Power Bars** removes the power bar from damage dealers and lets the health bar use the
space. Players without an assigned role keep their bar. Buff and debuff icons stay where they would sit above a
power bar, because that position is shared with Blizzard's protected private aura system.

### Unit Frames

**Health Bar Color** (Player, Target, Focus, Target of Target and Focus Target frames) can be Default or Class /
Reaction. With Class / Reaction, players show in their class color, and everyone else is red, yellow or green
depending on how they feel about you, or grey when they're tapped by someone else or offline. Each frame has its
own setting, so you can color your target by class and keep your own frame green.

### Tooltip

**Anchor** (HUD Tooltip) keeps tooltips at their Edit Mode position or attaches them to your cursor. With Cursor
selected, the X Offset and Y Offset sliders move the tooltip away from the cursor, and you can also type an exact
value into the box beside each slider. At 0, 0 the tooltip's bottom left corner sits right at the cursor. Only
tooltips that would normally appear at the Edit Mode position follow the cursor. Tooltips that a frame places
next to itself stay where they are.

**Hide Health Bar** (HUD Tooltip) removes the health bar that appears under the tooltip for players and NPCs.

**Instant Fade** (HUD Tooltip) makes the tooltip disappear the moment your mouse leaves a unit or object in the
world, or a unit frame, instead of slowly fading out.

### Text

**Hide Portrait Combat Text** (Player Frame) hides the damage, healing and miss numbers that flash over your
portrait. **Hide Player Name** removes your name from the Player Frame.

**Level Scale** (Player, Target and Focus Frames) makes the round level badge bigger or smaller, from 50% to
200%. It grows around its center, so it stays in place on the frame.

**Class icon portraits** bring Blizzard's two Interface options into Edit Mode. The Player Frame gets the one
that replaces your own portrait with your class icon. The Target, Focus, Target of Target and Focus Target frames
get the one for other players. Both are shared with Blizzard's options, so changing them in either place updates
the other.

**Status Text** (Player, Target and Focus Frames) is Blizzard's own Status Text option from the Interface
settings, available right in Edit Mode: Numeric Value, Percentage, Both or None. Like the original it applies to
every unit frame, and changing it in either place updates the other.

**Keybind Text** on every action bar can be Default, Short or Hidden. Short turns Shift + Mouse Button 4 into
`SM4`, Ctrl + Numpad 1 into `CN1` and Mouse Wheel Up into `WU`. Letters and function keys keep their normal names
with the modifier in front, like `SQ` or `CF1`. Gamepad bindings and the out of range dot are left alone.

**Experience Text** and **Reputation Text** can show Current / Max (the default), a percentage, or both. The
setting follows the bar type, whichever status bar slot it ends up in.

### More frames you can move

Some frames have no place in Blizzard's Edit Mode. EditTime gives them selection boxes that look and behave like
Blizzard's: click one to select it, drag it to move it, and use Reset To Default Position to put it back.

| Frame            | Notes                                                              |
|------------------|--------------------------------------------------------------------|
| Target of Target | Saved relative to the Target Frame, so it still follows it         |
| Focus Target     | Saved relative to the Focus Frame, so it still follows it          |
| Toasts           | Can grow up (the default) or down                                  |
| Loot Rolls       | Can grow up (the default) or down                                  |

With Edit Mode's Snap option turned on, these frames snap just like Blizzard's own: to the grid, the edges and
center of the screen, and the edges and corners of other frames, with the same red guide lines while you drag.
Blizzard's frames don't snap to them in return, and the arrow keys don't nudge them. Both would require changing
Edit Mode's internal data, which EditTime avoids.

## Installation

Copy the `EditTime` folder into:

```
World of Warcraft\_forever_\Interface\AddOns\
```

so that `EditTime.toc` sits at `...\Interface\AddOns\EditTime\EditTime.toc`.

## Compatibility

EditTime works with Blizzard's own Edit Mode and default frames. Addons that replace those frames entirely, or
that add their own options to the Edit Mode settings window, may overlap with what EditTime does.

## How EditTime stays safe

EditTime is built so it never causes "Interface action failed because of an AddOn" errors.

* It never replaces or edits Blizzard's code or Edit Mode's saved data. It only reacts after Blizzard has done
  its own work.
* Changes to protected frames, such as the party and raid frames, are only made out of combat.
* Frames that share a layout with the action bars are faded rather than hidden, so their layout stays untouched.
* Some unit information is hidden from addons in certain places. When EditTime can't be certain about something,
  it leaves the frame exactly as Blizzard drew it.

## License

MIT. See [LICENSE](LICENSE).

## Development

EditTime embeds no libraries. Releases are packaged by
[BigWigsMods/packager](https://github.com/BigWigsMods/packager) on tag push.

To work on it, link the repository into your AddOns folder:

```
mklink /J "<WoW folder>\_forever_\Interface\AddOns\EditTime" "<path to this repository>"
```

The addon list icon is built from `Gallery/EditTimeLogo.png` with `python tools/build_logo.py`.

To check for taint, run `/console taintLog 1`, play for a while, then look for EditTime in `Logs\taint.log`.
