# Un calcul d'horloges pour Faust

**[Brouillon v0 — document de travail, 12 novembre 2026]**

Objet : poser la théorie des horloges qui servira de base à la réimplémentation de
`ondemand`, `upsampling` et `downsampling` sur la lignée `master-dev-certification`.
Ce document ne spécifie que la logique des horloges ; il ne décrit pas encore
l'implémentation. Les propositions notées **[P]** sont des choix de conception
soumis à discussion, les points notés **[Q]** sont des questions ouvertes.

Sources : `spec.md` (ondemand v5), les documents Expressive E (`signaux.md`,
`compilation.md`, `dependencies.md`), les slides IFC-24, le code de
`master-dev-ocpp-od-fir-2-FIR20` (dernière implémentation à horloges) et celui de
`master-dev-certification-3` (la branche `-certification-4` n'est pas publiée à ce
jour).

## 1. Constat : l'horloge est déjà là, sous quatre déguisements

`certification-3` n'a aucun constructeur d'horloge, mais quatre mécanismes y
répondent déjà à la question « à quels instants ce signal est-il calculé ? » :

| Mécanisme existant | Question à laquelle il répond | Où |
|---|---|---|
| Variabilité `kKonst`/`kBlock`/`kSamp` et calculabilité `kComp`/`kInit`/`kExec` | init, une fois par bloc, ou à chaque échantillon ? | `VariabilityAlgebra`, `ComputabilityAlgebra` (`signals/sigattributes.cpp`) |
| Annotation de condition (`conditionAnnotation`, `Statement(cond, …)`) | ce nœud n'est calculé que si la garde est vraie | `generator/compile_scal.cpp`, `tlib/dcond.hh` |
| Frontière d'affichage (`computeDisplayFrontier`, `controlCS`) | les cônes des bargraphs sont évalués une fois par bloc, sur les valeurs de fin de bloc | `generator/compile_scal.cpp` |
| Générateurs de tables (`sigGen`) | un signal entier calculé hors temps réel, à l'initialisation | tables, waveforms |

L'ancienne implémentation (`FIR20`) ajoutait un cinquième mécanisme, séparé des
quatre autres : l'environnement d'horloge `HE ::= nil | (HE, slotenv, path, box, H, …)`,
porté par des nœuds enveloppes `sigClocked(env, s)`.

La thèse de ce document est que ces cinq mécanismes sont des instances d'une seule
notion, et qu'un seul calcul peut les couvrir.

## 2. Qu'est-ce qu'une horloge ?

### 2.1 Définition

Une **horloge** est soit l'horloge racine, soit une horloge dérivée d'une horloge
parente par un **signal de cadence** :

$$c ::= \mathbf{K} \;\mid\; p \triangleright_\rho r$$

- $p$ est l'horloge parente ;
- $r$ est un signal entier positif ou nul, défini sur $p$ : $r(t)$ est le **nombre de
  tops de $c$ pendant le top $t$ de $p$** ;
- $\rho \in \mathbb{Q}^+$ est le **rapport de fréquence nominal** déclaré (voir 2.4).

### 2.2 Sémantique : les tops

L'ensemble des tops d'une horloge est défini par récurrence :

$$\mathrm{Tops}(\mathbf{K}) = \{0\} \qquad
\mathrm{Tops}(p \triangleright r) = \{(t,j) \mid t \in \mathrm{Tops}(p),\ 0 \le j < r(t)\}$$

ordonné lexicographiquement. Cet ensemble est isomorphe à un segment initial de
$\mathbb{N}$ : c'est le **temps local** de l'horloge. Un signal d'horloge $c$ est une
fonction $\mathrm{Tops}(c) \to \mathbb{R}$, nulle avant le premier top, comme tout
signal Faust.

Le compteur cumulé $N_c(t) = \sum_{i \le t} r(i)$ relie temps parent et temps local.
On retrouve les fonctions de la spec v5 : $h^+(t) = N_c(t) - 1$ (dernier top local
achevé à la fin du top parent $t$) et $h^*(n) = \min\{t \mid N_c(t) > n\}$ (top parent
qui contient le top local $n$).

### 2.3 Les trois primitives sont une seule construction

| Primitive | Cadence $r$ | $\rho$ | Code produit par `FIR20` |
|---|---|---|---|
| `ondemand(P)(h)` | $h \in \{0,1\}$ | $1$ | `if (h) {…}` |
| `upsampling(P)(N)` | $N$ | $N$ | `for (j < N) {…}` |
| `downsampling(P)(N)` | $[t \bmod N = 0]$ | $1/N$ | `if (cpt % N == 0) {…}` |

`FIR20` traitait déjà un `ondemand` dont $h$ dépasse 1 comme « répéter $h$ fois ».
La cadence entière générale en est la formulation directe.

### 2.4 La fréquence nominale

$\rho$ n'affecte pas les tops. Il sert uniquement à donner la fréquence
d'échantillonnage vue à l'intérieur : $\mathrm{SR}_c = \rho \cdot \mathrm{SR}_p$.
C'est le comportement de `FIR20` (multiplication pour US, division pour DS,
inchangé pour OD).

### 2.5 Temps différé, contrôle, audio : une seule chaîne **[P]**

Les horloges prédéfinies se construisent par la même opération $\triangleright$ :

```
K                    compilation : un top, valeur connue du compilateur
└─ I = K ▷ 1         initialisation : un top par instance, SR connue
   ├─ G = I ▷ n      générateur de table : n tops, temps différé
   └─ B = I ▷ ω      bloc : un top par appel de compute()
      └─ S = B ▷ count   échantillon : count tops par bloc
         ├─ S ▷ h          ondemand
         ├─ S ▷ N          upsampling
         └─ S ▷ [t%N=0]    downsampling
```

Conséquences :

- **Audio rate et control rate.** L'horloge échantillon est un *upsampling* de
  l'horloge bloc par le signal `count`. Un slider est un signal sur $\mathbf{B}$.
  La variabilité devient la projection de l'horloge sur le préfixe
  $\mathbf{K}/\mathbf{I}/\mathbf{B}/\mathbf{S}$ : `kKonst` correspond à
  $\mathbf{K}$ ou $\mathbf{I}$, `kBlock` à $\mathbf{B}$, `kSamp` à $\mathbf{S}$ et
  au-delà.
- **Temps différé.** Un signal en temps différé est un signal sur une horloge finie,
  sœur de $\mathbf{B}$ sous $\mathbf{I}$. Tous ses tops ont lieu pendant l'unique top
  de $\mathbf{I}$. Vu du temps réel, il est donc entièrement disponible, sous forme de
  table à accès aléatoire. C'est exactement `sigGen`.
- **Horloges d'environnement.** $\mathbf{B}$ et $\mathbf{S}$ ont des cadences
  imposées par l'hôte ($\omega$, `count`). La sémantique d'un programme ne doit pas en
  dépendre (voir 4.4).

## 3. Quand deux horloges sont-elles compatibles ?

Trois relations distinctes, à ne pas confondre :

**Égalité.** Deux horloges sont égales si elles ont même parent, même $\rho$ et même
signal de cadence. Les signaux de cadence sont comparés par identité d'arbre après
mise en forme normale (hash-consing). **[P]** L'identité est donc *structurelle* et non
nominale : deux `ondemand` pilotés par le même $h$ partagent leur horloge. `FIR20`
faisait l'inverse (identité par `slotenv` et `path`), ce qui interdit la fusion de 5.3.

**Ordre de portée** $c_1 \preceq c_2$ : $c_1$ est un ancêtre de $c_2$, ou lui est
égale. C'est un ordre d'arbre, de minimum $\mathbf{K}$. Il signifie : *un signal de
$c_1$ est utilisable sur $c_2$* (voir 4.1).

**Compatibilité.** Deux horloges sont compatibles si elles sont comparables pour
$\preceq$. Leur borne supérieure $c_1 \sqcup c_2$ est alors la plus profonde. Deux
horloges incomparables (deux sœurs, par exemple) n'ont pas de borne supérieure : leurs
signaux ne se combinent qu'après remontée explicite vers un ancêtre commun.

**Ordre de densité.** $c = p \triangleright r$ est plus *rare* que $p$ si $r \le 1$,
plus *dense* si $r \ge 1$. Cet ordre ne sert pas à la correction mais au coût : il
décide où il est avantageux de placer un calcul (voir 6).

## 4. Les signaux et leurs horloges

### 4.1 Sous-typage : l'entrée dans une horloge est implicite **[P]**

Un signal $x$ d'horloge $p \preceq c$ vu depuis $c$ vaut, au top $(t,j)$, la valeur
$x(t)$ : c'est l'échantillonnage $x \downarrow c$ de la spec v5. Cette coercition est
toujours définie et n'a pas besoin de nœud. C'est déjà ainsi qu'un slider est utilisé
dans la boucle d'échantillons.

### 4.2 Où l'horloge est-elle écrite dans le terme ? **[P]**

Une opération sans mémoire commute avec l'échantillonnage :
$\star(x_1, x_2) \downarrow c = \star(x_1 \downarrow c,\ x_2 \downarrow c)$. Son
horloge se déduit donc de ses arguments. Seuls les constructeurs qui portent un
**état** ont besoin d'une horloge explicite, parce que l'état avance au rythme d'une
horloge précise :

```faust
ramp = +(1) ~ _;
process = ramp, ondemand(ramp);   // deux rampes distinctes, deux états distincts
```

Proposition : chaque constructeur à état reçoit son horloge en **argument**, et
l'horloge est un terme ordinaire, hash-consé, dont la cadence $r$ est un sous-arbre
visité par toutes les transformations.

| Constructeur | Horloge |
|---|---|
| `Delay`$^c(x, d)$, `Prefix`$^c$, `FIR`$^c$, `IIR`$^c$, `IRM`$^c$ | argument $c$ |
| groupe récursif $W^c$, `Proj`$(i, W^c)$ | argument $c$ du groupe |
| `WRTbl`$^c$ (écriture de table) | argument $c$ |
| `Up`$^c(y)$, `ZeroPad`$^c(x)$ | argument $c$ |

Cela remplace les enveloppes `sigClocked`, qui obligeaient chaque règle de réécriture
à savoir les traverser (`normalize`, `revealFIR`, `revealIIR`, élimination des
récursions dégénérées). Cela corrige aussi un défaut de `FIR20` : l'environnement y
embarquait le signal $H$ brut, que les passes ne transformaient jamais.

### 4.3 Règles d'horloge

On note $\vdash s : c$ pour « $s$ est défini sur $c$ », $c$ étant la plus petite
horloge possible (**horloge de définition**).

$$\frac{}{\vdash k : \mathbf{K}} \quad
\frac{}{\vdash \mathrm{SR} : \mathbf{I}} \quad
\frac{}{\vdash \mathit{slider} : \mathbf{B}} \quad
\frac{}{\vdash \mathit{input}_i : \mathbf{S}}$$

$$\frac{\vdash s_i : c_i \quad \text{les } c_i \text{ forment une chaîne}}
{\vdash \star(s_1,\ldots,s_n) : \bigsqcup_i c_i}\ (\textit{op})$$

$$\frac{\vdash x : c_x \preceq c \quad \vdash d : c_d \preceq c}
{\vdash \mathtt{Delay}^c(x,d) : c}\ (\textit{delay})
\qquad
\frac{\forall j.\ \vdash \mathrm{def}_j(W) : c_j \preceq c}
{\vdash \mathtt{Proj}(i, W^c) : c}\ (\textit{rec})$$

$$\frac{c = p \triangleright r \quad \vdash y : c_y \preceq c}
{\vdash \mathtt{Up}^c(y) : p}\ (\textit{up})
\qquad
\frac{c = p \triangleright r \quad \vdash x : c_x \preceq p}
{\vdash \mathtt{ZeroPad}^c(x) : c}\ (\textit{pad})$$

$$\frac{\vdash r : c_r \preceq p \quad r \in \mathbb{N} \text{ (prouvé par intervalle)}}
{p \triangleright_\rho r \ \text{bien formée}}\ (\textit{clk})$$

Remarques :

- La règle (*delay*) contient le fait que « c'est le retard qui rend un signal
  audio » : `slider'` est `Delay`$^{\mathbf{S}}$`(slider, 1)`.
- La règle (*rec*) est une **vérification**, pas une inférence. Le point fixe sur les
  groupes récursifs de `clkEnvInference` disparaît, puisque l'horloge du groupe est
  écrite dans le terme.
- `Up` est le seul constructeur qui fait remonter d'un niveau.
- (*clk*) : la positivité et l'intégralité de $r$ sont des obligations de
  certification, au même titre que les bornes d'index de table. `FIR20` se contentait
  d'un avertissement.

### 4.4 Sémantique des traversées

- **Maintien** : $\mathtt{Up}^c(y)(t) = y(t, r(t)-1)$ si $r(t) > 0$, sinon la valeur
  précédente, et $0$ avant le premier top de $c$. C'est $y \uparrow h$.
- **Bourrage de zéros** : $\mathtt{ZeroPad}^c(x)(t,j) = x(t)$ si $j = r(t)-1$, sinon
  $0$. `FIR20` l'applique aux entrées de `upsampling`.
- **Retard** : $\mathtt{Delay}^c(x,d)$ retarde de $d$ tops *de $c$*.

Traduction des primitives de boîtes, pour $P : n \to m$ et $c = p \triangleright r$ :

$$[\![\mathtt{ondemand}(P)]\!]_p(r, x_1..x_n) = (\mathtt{Up}^c(y_1)..\mathtt{Up}^c(y_m))
\quad\text{où}\quad (y_1..y_m) = [\![P]\!]_c(x_1..x_n)$$

L'indice de $[\![\cdot]\!]$ est l'horloge lexicale courante, que la propagation donne
en argument à chaque constructeur à état qu'elle crée. Un *sample and hold*
`ondemand(_)` se réduit à `Up`$^c(x)$.

**Frontière d'observation.** Une remontée de $\mathbf{S}$ vers $\mathbf{B}$ dépend de
la taille des blocs. Elle n'est admise que vers un puits (bargraph) et ne peut pas
réalimenter un calcul. C'est la frontière d'affichage actuelle, reformulée.

## 5. Lois algébriques

1. **Distribution** : $\star(x_1,x_2) \downarrow c = \star(x_1 \downarrow c, x_2 \downarrow c)$.
   Elle fonde le sous-typage implicite.
2. **Retards** : $\mathtt{Delay}^c(\mathtt{Delay}^c(x,a),b) = \mathtt{Delay}^c(x,a+b)$,
   seulement à horloge égale. Un retard ne commute pas avec un changement d'horloge.
3. **Fusion** : si $r \le 1$ (prouvé par intervalle), $\mathtt{Up}^c(y)$ vu depuis $c$
   vaut $y$. C'est la note « $\uparrow h : \downarrow h$ est l'identité » de la spec v5.
   D'où `ondemand(P)(h) : ondemand(Q)(h)` $=$ `ondemand(P:Q)(h)`, à condition que
   l'égalité d'horloge soit structurelle. Pour $r > 1$ la loi est fausse :
   $\mathtt{Up}^c(y)$ n'est disponible qu'après le dernier sous-top.
4. **Composition** : pour des cadences booléennes, $(p \triangleright h_1) \triangleright h_0$
   a les mêmes tops que $p \triangleright (h_1 \cdot \mathtt{Up}(h_0))$. C'est
   l'opérateur $h_0 \otimes h_1$ de la spec v5, dont l'associativité est celle de la
   concaténation des chemins dans l'arbre.
5. **Cas dégénérés** : $r = 1$ donne $c \cong p$ (le corps est mis en ligne), $r = 0$
   donne une horloge sans top (toutes les sorties valent $0$). `FIR20` les traite déjà
   à la propagation.

## 6. Horloge de définition, de demande, d'exécution

Pour un signal sans état, l'horloge de définition n'est qu'une borne. Trois attributs :

- **Définition** $\mathrm{def}(s)$ : synthétisé, de bas en haut (section 4.3). C'est la
  première horloge où la valeur existe.
- **Demande** $\mathrm{dem}(s)$ : hérité, de haut en bas. Ce sont les horloges des
  consommateurs.
- **Exécution** $\mathrm{exe}(s)$ : l'horloge où le code est émis, avec
  $\mathrm{def}(s) \preceq \mathrm{exe}(s) \preceq$ l'ancêtre commun des demandes.

Pour un nœud à état, $\mathrm{exe} = \mathrm{def}$, sans choix possible : un écho
inaudible vieillit quand même. C'est la règle `isConditionBoundary` de
`certification-3`, qui devient ici une conséquence et non plus une liste de cas.

Pour un nœud sans état, le choix est une optimisation guidée par la densité :

- descendre vers une horloge plus rare réalise l'appel par nécessité (ne pas calculer
  l'entrée d'un `ondemand` quand il ne tourne pas) ;
- remonter vers une horloge moins dense réalise la sortie des invariants de boucle
  (calcul des sliders hors de la boucle d'échantillons, entrée d'un `upsampling`).

Les gardes de `-lazyselect` sont alors des horloges booléennes anonymes sur du code
sans état, et `enable`/`control` (annoncés comme remplacés par `ondemand` dans
`compile_scal.hh`) n'ont plus de raison d'être.

## 7. Causalité, mémoire, certification

- **Causalité.** Pendant un top $t$ de $p$ : on calcule $r(t)$ et les valeurs entrantes,
  puis les $r(t)$ tops de $c$, puis les `Up`$^c$. Une région d'horloge est donc un nœud
  du graphe de son parent. Toute boucle qui traverse une frontière doit contenir un
  retard. $r$ ne peut pas dépendre instantanément d'une sortie de sa propre horloge.
- **Mémoire.** L'état appartient au signal, pas à l'horloge. Chaque horloge a en
  revanche son propre index de temps (un IOTA par horloge, comme dans `FIR20`).
- **Horizon.** L'analyse d'intervalles affine en temps de `sighorizon` compte en
  échantillons. Sur $c = p \triangleright r$, le temps local est borné par
  $\sup(r)$ fois le temps parent. Une cadence d'`upsampling` doit donc être bornée,
  ce qui s'ajoute à (*clk*).
- **Invariant de la branche.** Une seule référence sémantique, indépendante du
  backend, de la vectorisation et de l'ordonnancement. La sémantique par tops de 2.2
  fournit cette référence.
- **Vectorisation.** Une horloge de cadence constante (US, DS) est *périodique* : sa
  région peut devenir une boucle sœur de longueur $N \cdot \mathit{count}$ ou
  $\mathit{count}/N$. Une horloge dépendante des données reste scalaire dans sa région.
  `FIR20` refusait `-vec` en bloc.

## 8. Ce qui se réutilise, ce qui change

**De `certification-3`**

| Existant | Rôle dans le calcul d'horloges |
|---|---|
| `SignalAlgebra<V>` et `FixPointIterator` | `ClockAlgebra` pour l'horloge de définition. « Rien n'est défini par défaut » impose une règle par constructeur |
| `tlib/descend.hh`, régime B | horloge de demande. Le commentaire prévoit déjà cet usage |
| `VariabilityAlgebra`, `ComputabilityAlgebra` | deviennent des projections de l'horloge. À conserver d'abord en parallèle, avec un test de cohérence |
| `conditionAnnotation`, `Statement(cond)`, `ControlInst` | émission des régions à cadence booléenne |
| frontière d'affichage, `controlCS` | instance de `Up` de $\mathbf{S}$ vers $\mathbf{B}$ |
| zones de `Klass` (init, bloc, boucle) | la chaîne $\mathbf{I}/\mathbf{B}/\mathbf{S}$ |
| `GroupPlan` (arbre de groupes) | hôte naturel d'un groupe « région d'horloge » |
| boucles internes de `-fam` | modèle d'émission pour la boucle d'un `upsampling` |
| IOTA global | à rendre propre à chaque horloge |
| portes de test (canonicité, déterminisme, mémoire) | à étendre aux programmes à horloges |

**De `FIR20`**

| Élément | Devenir |
|---|---|
| lexer, parser, boîtes, typage $(u+1) \to v$, schémas | repris tels quels |
| `propagate(clockenv, …)` et adaptation de `SR` | repris, l'environnement devient le terme $c$ |
| `TempVar`, `PermVar`, formes `if` / `for` / compteur | repris à l'émission seulement |
| `sigClocked`, `sigDoubleClocked` | remplacés par l'argument d'horloge des constructeurs à état |
| `sigOD`/`sigUS`/`sigDS` et `sigSeq` (type factice) | remplacés par `Up`$^c$, typé normalement. La région se déduit de $\mathrm{exe}$ |
| `clkEnvInference` (point fixe) | remplacé par une vérification |
| identité nominale des environnements | identité structurelle |
| erreurs sans localisation, refus de `-vec` | à corriger |

## 9. Questions ouvertes

- **[Q1]** Entrée implicite (4.1) ou nœud `Down` explicite ? L'implicite donne la
  canonicité sans effort et un partage maximal. L'explicite rend la loi de fusion
  locale. Proposition : implicite dans la forme normale, explicite seulement à
  l'abaissement final.
- **[Q2]** Identité structurelle des horloges (3) : acceptée ? Elle suppose que les
  transformations soient déterministes sur les cadences.
- **[Q3]** `upsampling` : bourrage de zéros (comme `FIR20`) ou maintien pour les
  entrées ? Et la sortie : dernier sous-échantillon, ou décimation explicite ?
- **[Q4]** La chaîne $\mathbf{K}/\mathbf{I}/\mathbf{B}/\mathbf{S}$ remplace-t-elle la
  variabilité à terme, ou reste-t-elle une vue au-dessus de l'existant ?
- **[Q5]** Traversées vectorielles (`vectorize`/`serialize`, trames FFT,
  `interleave`) : une remontée qui *collecte* les $r(t)$ valeurs au lieu de maintenir
  la dernière. Le générateur de table en est déjà une. À prévoir dans les types dès
  maintenant ?
- **[Q6]** `switch(C0..Ck)` : horloges sœurs de cadences complémentaires. Faut-il une
  notion d'horloges *exclusives* pour partager l'état ou le code ?
- **[Q7]** Horloges périodiques : faut-il décider l'égalité au-delà de la syntaxe
  (US par $N$ suivi de DS par $N$) ?
- **[Q8]** Cadence définie sur $\mathbf{B}$ (ondemand piloté par un slider) : la région
  doit-elle sortir de la boucle d'échantillons ?
