// Attraction kind classification.
//
// themeparks.wiki tells us something is an ATTRACTION but not what sort it is.
// A ride that matched a coaster spec record is a coaster by definition;
// everything else is classified from its name.
//
// Park feeds are localised, so the rules cover the languages that actually turn
// up in the data — English, German, French, Spanish, Dutch, Italian and Chinese.
// Anything unrecognised stays "other", which is honest: a lot of these genuinely
// are game booths, playgrounds and character meets rather than rides.

const RULES = [
  // Order matters: first match wins. Water before dark, because "Splash
  // Mountain" is a water ride that would otherwise read as a dark ride.
  [
    /\b(water ?coaster|log ?flume|flume|rapids|river ?raft|splash|shoot the chutes?|water ?slide|aqua|lazy river|rambling river|endless river|river(?! ?(?:boat|steamer|cruise|railroad))|wave ?pool|wildwasser|wasserbahn|rivi[eè]re|bateau|r[ií]o|rio r[aá]pido|acqua|wildwater|waterbaan)\b|漂流|激流|水上|滑水|浪|瀑布/i,
    "water",
  ],
  [
    /\b(dark ?ride|haunted|haunt|ghost|mansion|spooky|adventure of|4-?d|3-?d|simulator|motion ?master|dungeon|geisterbahn|maison hant|casa embrujada|walkthrough|walk-?through|escape room)\b|鬼屋|幽灵|探险|奇幻/i,
    "dark",
  ],
  [
    /\b(theatre|theater|show|stage|spectacular|parade|cinema|imax|arena|live|concert|revue|meet ?(?:and|&) ?greet|character|greeting|fireworks|s?pectacle|vorstellung|espect[aá]culo)\b|剧场|表演|演出|秀/i,
    "show",
  ],
  [
    /\b(railroad|rail ?way|monorail|tram|sky ?ride|sky ?way|cable ?car|gondola|chairlift|funicular|ferry|riverboat|steamer|transport|shuttle|people ?mover|bahnhof|eisenbahn|t[eé]l[eé]ph[eé]rique|tren|treno)\b|小火车|观光车|缆车|列车/i,
    "transport",
  ],
  [
    /\b(carousel|carrousel|merry-?go-?round|ferris|observation ?wheel|big ?wheel|swing|drop ?tower|free ?fall|tower of|teacups?|tea ?cup|bumper|dodgem|scrambler|waltzer|top ?spin|pirate ?ship|frisbee|troika|enterprise|breakdance|round ?up|tilt-?a-?whirl|flying ?(?:carpet|scooters?)|balloon|convoy|jeep|flying ?school|karussell|riesenrad|freifallturm|grande ?roue|manège|noria|giostra|reuzenrad|zweefmolen)\b|转马|旋转|摩天轮|海盗船|跳楼机|太空|摆锤|碰碰车|飞椅|飞机/i,
    "flat",
  ],
  [
    /\b(playground|play ?area|climbing|maze|arcade|games?|midway ?games?|petting|zoo|aquarium|exhibit|garden|museum|gift ?shop|photo|nets?|sand ?pit|splash ?pad|treehouse|tree ?house)\b|游乐场|儿童/i,
    "other",
  ],
];

// Explicit coaster words, for rides that have no Wikipedia article.
const COASTER_WORDS =
  /\b(roller ?coaster|coaster|achterbahn|montagne ?russe|monta[ñn]a ?rusa|achtbaan|montagne ?russe|rollercoaster|wild ?mouse|wilde ?maus|mine ?train|bobsled|boomerang|corkscrew)\b|过山车|云霄飞车|矿山车/i;

/**
 * Best-effort kind from an attraction's name. Only called when no spec record
 * told us the kind outright, so "other" is a legitimate answer rather than a
 * failure — plenty of these really are game booths and character meets.
 *
 * @param {string} name
 * @param {{entityType?: string}} [ctx]
 * @returns {"coaster"|"dark"|"water"|"show"|"flat"|"transport"|"other"}
 */
export function classify(name, { entityType = "ATTRACTION" } = {}) {
  if (entityType === "SHOW") return "show";

  // A water coaster is still a water ride, so the rules run before this check.
  for (const [re, kind] of RULES) if (re.test(name)) return kind;

  if (COASTER_WORDS.test(name)) return "coaster";
  return "other";
}
