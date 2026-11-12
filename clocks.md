# Un calcul d'horloges pour Faust

**[Brouillon v1 — document de travail, 12 novembre 2026]**

Objet : poser la théorie des horloges qui servira de base à la réimplémentation de
`ondemand`, `upsampling` et `downsampling` sur la lignée `master-dev-certification`.
Ce document ne spécifie que la logique des horloges ; il ne décrit pas encore
l'implémentation. Les propositions notées **[P]** sont des choix de conception
soumis à discussion, les points notés **[Q]** sont des questions ouvertes.

Changements depuis la v0 : une horloge est un ensemble d'instants ; une seule règle
de lecture remplace les opérateurs de montée et de descente ; convention « début »
pour la subdivision ; la compilation n'est plus une horloge.

Sources : `spec.md` (ondemand v5), les documents Expressive E, les slides IFC-24, le
code de `master-dev-ocpp-od-fir-2-FIR20` (dernière implémentation à horloges) et celui
de `master-dev-certification-3` (la branche `-certification-4` n'est pas publiée à ce
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
quatre autres : l'environnement d'horloge, porté par des nœuds enveloppes
`sigClocked(env, s)`.

La thèse de ce document est que ces cinq mécanismes sont des instances d'une seule
notion, et qu'un seul calcul peut les couvrir.

## 2. Instants et horloges

### 2.1 Les instants

On se donne un ensemble $\mathbb{T}$ d'**instants**, totalement ordonné. Une
**horloge** est une partie de $\mathbb{T}$ ; ses éléments sont ses **tops**. Un signal
d'horloge $H$ est une fonction $H \to \mathbb{R}$.

Les horloges forment donc un treillis pour l'inclusion, avec l'union et
l'intersection. $H_1 \subseteq H_2$ se lit « $H_1$ est plus rare que $H_2$ ».

### 2.2 Les horloges naturelles

Elles sont imposées par l'hôte, pas par le programme.

| Horloge | Tops |
|---|---|
| $\mathbf{S}$ | les échantillons $0, 1, 2, \ldots$ |
| $\mathbf{B}$ | les débuts de blocs : $\mathbf{B} \subset \mathbf{S}$ |
| $\mathbf{B}'$ | les fins de blocs (dernier échantillon de chaque bloc) : $\mathbf{B}' \subset \mathbf{S}$ |
| $\mathbf{I}$ | l'instant d'initialisation $\iota$, antérieur à l'échantillon $0$ |

Les sliders sont des signaux sur $\mathbf{B}$, les constantes qui dépendent de `SR`
des signaux sur $\mathbf{I}$. On sait que $\mathbf{B} \subset \mathbf{S}$ sans savoir
quel sous-ensemble : la sémantique d'un programme ne doit pas en dépendre (voir 4.5).

La compilation n'est pas une horloge. Un calcul fait par le compilateur relève de
l'étagement, pas d'un instant d'exécution.

### 2.3 Les horloges dérivées

Une horloge dérivée est construite à partir d'une horloge parente $p$ et d'un
**signal de cadence** $r$, entier positif ou nul, lisible sur $p$ :

$$p \triangleright r = \{\tau \cdot \tfrac{j}{r(\tau)} \mid \tau \in p,\ 0 \le j < r(\tau)\}$$

$r(\tau)$ est le nombre de tops de la nouvelle horloge attachés au top $\tau$ de $p$.
L'instant $\tau \cdot q$, pour une fraction $q \in [0,1[$, est situé entre $\tau$ et
le top suivant de $p$, à la proportion $q$ de l'intervalle. Les instants de
$\mathbb{T}$ sont ainsi des suites finies de fractions, ordonnées lexicographiquement.

**Convention « début ».** $\tau \cdot 0 = \tau$ : le premier sous-instant *est*
l'instant parent.

Trois cas :

- $r \le 1$ : **sélection**. $p \triangleright r \subseteq p$.
- $r \ge 1$ : **subdivision**. $p \subseteq p \triangleright r$, grâce à la convention
  « début ».
- $r$ quelconque : ni l'un ni l'autre ; `FIR20` admettait déjà un `ondemand` dont $h$
  dépasse 1, compris comme « répéter $h$ fois ».

| Primitive | Cadence $r$ | Relation à $p$ | Code produit par `FIR20` |
|---|---|---|---|
| `ondemand(P)(h)` | $h \in \{0,1\}$ | $\subseteq p$ | `if (h) {…}` |
| `downsampling(P)(N)` | $[t \bmod N = 0]$ | $\subseteq p$ | `if (cpt % N == 0) {…}` |
| `upsampling(P)(N)` | $N$ | $\supseteq p$ | `for (j < N) {…}` |

Les trois primitives sont donc une seule construction. Avec la position fractionnaire,
un `upsampling` par 2 est inclus dans un `upsampling` par 4 du même parent.

### 2.4 Le temps différé

Le remplissage d'une table de taille $n$ est une subdivision de l'instant
d'initialisation : $\mathbf{G}_n = \mathbf{I} \triangleright n$. Ses $n$ tops sont
tous antérieurs à l'échantillon $0$ et ne sont pas des tops de $\mathbf{S}$. C'est la
même construction qu'un `upsampling`, appliquée à $\mathbf{I}$ au lieu de $\mathbf{S}$.

Seule la sortie diffère : la table *collecte* les $n$ valeurs au lieu de n'en lire
qu'une. Elle est disponible après le dernier top de $\mathbf{G}_n$, donc pour tous les
lecteurs en temps réel.

### 2.5 La fréquence nominale

Chaque horloge dérivée déclare un rapport $\rho$ : $N$ pour un `upsampling`, $1/N$
pour un `downsampling`, $1$ pour un `ondemand`. Il n'affecte pas les tops. Il donne la
fréquence d'échantillonnage vue à l'intérieur : $\mathrm{SR}_c = \rho \cdot \mathrm{SR}_p$,
comme dans `FIR20`.

## 3. La règle de lecture

### 3.1 Définition

La valeur d'un signal $x$ d'horloge $H$, **lue** à un instant $t$ quelconque de
$\mathbb{T}$, est sa valeur au dernier top de $H$ qui ne dépasse pas $t$ :

$$x\lfloor t \rfloor = x(\max\{u \in H \mid u \le t\}) \qquad \text{et } 0 \text{ s'il n'y a pas encore eu de top}$$

C'est l'instant le plus proche qui respecte la causalité. La règle est définie pour
toute paire d'horloges, comparables ou non. Le « $\le$ » admet la lecture au même
instant ; un cycle de dépendances doit donc contenir un retard, comme aujourd'hui.

### 3.2 Les trois cas

Soit un calcul fait sur $H_0$, qui lit un argument d'horloge $H_i$ :

| Cas | Ce que fait la lecture | Perte |
|---|---|---|
| $H_i \subseteq H_0$ (argument plus rare) | maintien de la dernière valeur ($\uparrow$ de la spec v5) | non |
| $H_i \supseteq H_0$ (argument plus dense) | échantillonnage ($\downarrow$ de la spec v5) | oui |
| incomparables | maintien puis échantillonnage | oui |

**Compatibilité.** Deux horloges sont compatibles si elles sont comparables pour
l'inclusion. Ce n'est pas une condition de validité : `ondemand(P)(h1) : ondemand(Q)(h2)`
met en jeu deux horloges incomparables et reste un programme légitime. La
compatibilité dit quand la lecture se réduit à un maintien ou à un échantillonnage pur.

### 3.3 Loi de cohérence

Si $H \subseteq H'$, lire $x$ (d'horloge $H$) directement ou en passant par $H'$ donne
le même résultat :

$$x\lfloor \lfloor t \rfloor_{H'} \rfloor = x\lfloor t \rfloor$$

Passer par une horloge plus dense est toujours neutre. Passer par une horloge plus rare
perd de l'information : c'est une véritable opération, qui doit être écrite.

## 4. Les signaux et leurs horloges

### 4.1 Calculs sans mémoire

Un calcul sans mémoire n'a pas d'horloge propre. Sa valeur ne peut changer qu'aux
instants où l'un de ses arguments change. Son horloge est donc **l'union** des horloges
de ses arguments. Quand elles sont comparables, c'est la plus dense.

### 4.2 Calculs avec mémoire

Un calcul avec mémoire impose son horloge, parce que son état avance au rythme d'une
horloge précise :

```faust
ramp = +(1) ~ _;
process = ramp, ondemand(ramp);   // deux rampes distinctes, deux états distincts
```

**[P]** Chaque constructeur à état reçoit son horloge en **argument**. L'horloge est
un terme ordinaire, hash-consé, dont la cadence $r$ est un sous-arbre visité par
toutes les transformations.

| Constructeur | Horloge |
|---|---|
| `Delay`$^c(x, d)$, `Prefix`$^c$, `FIR`$^c$, `IIR`$^c$, `IRM`$^c$ | argument $c$ |
| groupe récursif $W^c$, `Proj`$(i, W^c)$ | argument $c$ du groupe |
| `WRTbl`$^c$ (écriture de table) | argument $c$ |
| `Sample`$^c(x)$, `ZeroPad`$^c(x)$ | argument $c$ |

Cela remplace les enveloppes `sigClocked`, qui obligeaient chaque règle de réécriture
à savoir les traverser. Cela corrige aussi un défaut de `FIR20` : l'environnement y
embarquait le signal $H$ brut, que les passes ne transformaient jamais.

### 4.3 L'échantillonnage, seule traversée explicite

D'après la loi de cohérence, le maintien n'a pas besoin de nœud. La lecture avec perte
en a besoin d'un :

$$\mathtt{Sample}^c(x) \text{ est le signal d'horloge } c \text{ qui vaut } x\lfloor t \rfloor \text{ en chaque top } t \text{ de } c$$

Traduction des trois primitives, pour $P : n \to m$ et $c = p \triangleright r$,
l'indice de $[\![\cdot]\!]$ étant l'horloge lexicale courante :

$$[\![\mathtt{clocked}(P)]\!]_p(r, x_1..x_n) = (\mathtt{Sample}^p(\mathtt{Sample}^c(y_1)), \ldots)
\quad\text{où}\quad (y_1..y_m) = [\![P]\!]_c(\mathtt{Sample}^c(x_1), \ldots)$$

Un signal extérieur capturé par $P$ (portée lexicale) est échantillonné de la même
façon. La traduction est uniforme ; ce sont les simplifications de la section 5 qui
font la différence entre les primitives :

- **`ondemand`, `downsampling`** ($c \subseteq p$) : les entrées sont réellement
  échantillonnées, `Sample`$^p$ en sortie s'efface. Un *sample and hold*
  `ondemand(_)` se réduit à `Sample`$^c(x)$.
- **`upsampling`** ($p \subseteq c$) : `Sample`$^c$ en entrée s'efface (l'entrée est
  maintenue sur tous les sous-instants), `Sample`$^p$ en sortie décime en gardant le
  **premier** sous-échantillon.

`ZeroPad`$^c(x)$ vaut $x$ au premier sous-instant et $0$ aux autres. C'est la variante
d'entrée d'un `upsampling` avec bourrage de zéros.

**Écart avec `FIR20`** : la sortie d'un `upsampling` y était le dernier
sous-échantillon, et le bourrage de zéros plaçait la valeur au dernier sous-instant.
L'entrée y était pourtant visible de tous les sous-instants, ce qui n'est cohérent
avec aucun ordre total des instants.

### 4.4 Règles d'horloge

On note $\vdash s : H$ pour « $H$ est l'horloge de $s$ ».

$$\frac{}{\vdash k : \mathbf{I}} \quad
\frac{}{\vdash \mathrm{SR} : \mathbf{I}} \quad
\frac{}{\vdash \mathit{slider} : \mathbf{B}} \quad
\frac{}{\vdash \mathit{input}_i : \mathbf{S}}$$

$$\frac{\vdash s_i : H_i}{\vdash \star(s_1,\ldots,s_n) : \bigcup_i H_i}\ (\textit{op})
\qquad
\frac{}{\vdash \mathtt{Sample}^c(x) : c}\ (\textit{sample})$$

$$\frac{\vdash x : H_x \subseteq c \quad \vdash d : H_d \subseteq c}
{\vdash \mathtt{Delay}^c(x,d) : c}\ (\textit{delay})
\qquad
\frac{\forall j.\ \vdash \mathrm{def}_j(W) : H_j \subseteq c}
{\vdash \mathtt{Proj}(i, W^c) : c}\ (\textit{rec})$$

$$\frac{\vdash r : H_r \subseteq p \quad r \in \mathbb{N} \text{ (prouvé par intervalle)}}
{p \triangleright r \ \text{bien formée}}\ (\textit{clk})$$

Remarques :

- (*delay*) et (*rec*) exigent des arguments plus rares que $c$ : leur lecture est
  alors sans perte. La propagation garantit cette condition en insérant `Sample`.
  Ce sont des **vérifications**, pas des inférences : le point fixe de
  `clkEnvInference` disparaît.
- (*delay*) contient le fait que « c'est le retard qui rend un signal audio » :
  `slider'` est `Delay`$^{\mathbf{S}}$`(slider, 1)`.
- (*clk*) : la positivité et l'intégralité de $r$ sont des obligations de
  certification. `FIR20` se contentait d'un avertissement.
- L'inclusion est décidée par des conditions suffisantes syntaxiques : sélection,
  subdivision, transitivité, et les cas périodiques.

### 4.5 Frontière d'observation

Un bargraph est un `Sample` vers $\mathbf{B}'$ (ou vers $\mathbf{B}$ : les deux
conviennent, la fin de bloc est seulement moins coûteuse à émettre). Le résultat dépend
de la taille des blocs. Un tel échantillonnage n'est admis que vers un puits et ne peut
pas réalimenter un calcul. C'est la frontière d'affichage actuelle, reformulée.

## 5. Lois algébriques

1. **Effacement** : $\mathtt{Sample}^c(x) = x$ si l'horloge de $x$ est incluse dans $c$.
2. **Absorption** : $\mathtt{Sample}^c(\mathtt{Sample}^{c'}(x)) = \mathtt{Sample}^c(x)$
   si $c \subseteq c'$.
3. **Distribution** : $\mathtt{Sample}^c(\star(x_1,x_2)) = \star(\mathtt{Sample}^c(x_1), \mathtt{Sample}^c(x_2))$.
4. **Retards** : $\mathtt{Delay}^c(\mathtt{Delay}^c(x,a),b) = \mathtt{Delay}^c(x,a+b)$,
   seulement à horloge égale.
5. **Fusion** : `ondemand(P)(h) : ondemand(Q)(h)` $=$ `ondemand(P:Q)(h)`. Elle découle
   de la loi 1, à condition que les deux horloges soient reconnues égales. Elle est
   fausse pour un `upsampling`, dont la sortie est décimée.
6. **Composition** : pour des cadences booléennes, $(p \triangleright h_1) \triangleright h_0$
   a les mêmes tops que $p \triangleright (h_1 \cdot h_0)$, $h_0$ étant lu sur $p$.
   C'est l'opérateur $h_0 \otimes h_1$ de la spec v5.
7. **Cas dégénérés** : $r = 1$ donne $p \triangleright r = p$, $r = 0$ donne l'horloge
   vide, dont tous les signaux se lisent $0$.

**Constante avant le premier top.** $\mathbf{I} \not\subseteq c$ en général, donc
`Sample`$^c(1)$ ne s'efface pas : il vaut $0$ jusqu'au premier top de $c$, puis $1$.
C'est la sémantique de la spec v5 pour `ondemand(1)`. Il s'efface si l'on prouve
$r(0) \ge 1$.

**Égalité des horloges. [P]** Deux horloges dérivées sont égales si elles ont même
parent et même signal de cadence, comparé par identité d'arbre après mise en forme
normale. L'identité est *structurelle*, alors que `FIR20` distinguait chaque instance.
La loi de fusion en dépend.

## 6. Horloge de définition, de demande, d'exécution

- **Définition** : l'horloge de la section 4.4, calculée de bas en haut.
- **Demande** : les horloges des consommateurs, propagée de haut en bas.
- **Exécution** : l'horloge où le code est émis.

Pour un nœud à état, l'exécution est la définition, sans choix possible : un écho
inaudible vieillit quand même. C'est la règle `isConditionBoundary` de
`certification-3`, qui devient une conséquence et non plus une liste de cas.

Pour un nœud sans état, la loi de cohérence laisse le choix : toute horloge qui
contient les instants demandés convient. Le choix est une optimisation :

- vers une horloge plus rare : appel par nécessité (ne pas calculer l'entrée d'un
  `ondemand` quand il ne tourne pas) ;
- vers une horloge moins dense : sortie des invariants de boucle (sliders hors de la
  boucle d'échantillons, entrée d'un `upsampling`).

Les gardes de `-lazyselect` sont alors des horloges booléennes anonymes sur du code
sans état, et `enable`/`control` (annoncés comme remplacés par `ondemand` dans
`compile_scal.hh`) n'ont plus de raison d'être.

## 7. Causalité, mémoire, certification

- **Causalité.** Une région d'horloge est un nœud du graphe de son parent. Toute
  boucle de dépendances doit contenir un retard. $r$ ne peut pas dépendre
  instantanément d'un signal de sa propre horloge.
- **Mémoire.** L'état appartient au signal, pas à l'horloge. Chaque horloge a son
  propre index de temps (un IOTA par horloge, comme dans `FIR20`). Lire un signal plus
  rare coûte une variable qui garde la dernière valeur (le `PermVar` de `FIR20`).
- **Horizon.** L'analyse d'intervalles affine en temps de `sighorizon` compte en
  échantillons. Sur $p \triangleright r$, le temps local est borné par $\sup(r)$ fois
  le temps parent. Une cadence de subdivision doit donc être bornée.
- **Invariant de la branche.** Une seule référence sémantique, indépendante du
  backend, de la vectorisation et de l'ordonnancement. Les sections 2 et 3 la
  fournissent.
- **Vectorisation.** Une horloge de cadence constante est *périodique* : sa région peut
  devenir une boucle sœur de longueur $N \cdot \mathit{count}$ ou $\mathit{count}/N$.
  Une horloge dépendante des données reste scalaire dans sa région. `FIR20` refusait
  `-vec` en bloc.

## 8. Ce qui se réutilise, ce qui change

**De `certification-3`**

| Existant | Rôle dans le calcul d'horloges |
|---|---|
| `SignalAlgebra<V>` et `FixPointIterator` | `ClockAlgebra` pour l'horloge de définition. « Rien n'est défini par défaut » impose une règle par constructeur |
| `tlib/descend.hh`, régime B | horloge de demande. Le commentaire prévoit déjà cet usage |
| `VariabilityAlgebra`, `ComputabilityAlgebra` | deviennent des projections de l'horloge. À conserver d'abord en parallèle, avec un test de cohérence |
| `conditionAnnotation`, `Statement(cond)`, `ControlInst` | émission des régions à cadence booléenne |
| frontière d'affichage, `controlCS` | instance de `Sample` vers $\mathbf{B}'$ |
| zones de `Klass` (init, bloc, boucle) | les horloges $\mathbf{I}$, $\mathbf{B}$, $\mathbf{S}$ |
| `GroupPlan` (arbre de groupes) | hôte naturel d'un groupe « région d'horloge » |
| boucles internes de `-fam` | modèle d'émission pour la boucle d'un `upsampling` |
| IOTA global | à rendre propre à chaque horloge |
| portes de test (canonicité, déterminisme, mémoire) | à étendre aux programmes à horloges |

**De `FIR20`**

| Élément | Devenir |
|---|---|
| lexer, parser, boîtes, typage $(u+1) \to v$, schémas | repris tels quels |
| `propagate(clockenv, …)` et adaptation de `SR` | repris, l'environnement devient le terme d'horloge |
| `TempVar`, `PermVar`, formes `if` / `for` / compteur | repris à l'émission seulement |
| `sigClocked`, `sigDoubleClocked` | remplacés par l'argument d'horloge des constructeurs à état |
| `sigOD`/`sigUS`/`sigDS`, `sigSeq`, `sigPermVar` | supprimés : le maintien est implicite, la région se déduit de l'horloge d'exécution |
| `sigTempVar` | devient `Sample`$^c$ |
| `clkEnvInference` (point fixe) | remplacé par une vérification |
| identité nominale des environnements | identité structurelle |
| sortie d'`upsampling` au dernier sous-échantillon | premier sous-échantillon (convention « début ») |
| erreurs sans localisation, refus de `-vec` | à corriger |

## 9. Questions ouvertes

- **[Q1]** Identité structurelle des horloges : acceptée ? Elle suppose que les
  transformations soient déterministes sur les cadences.
- **[Q2]** Lecture entre deux subdivisions non emboîtées (un `upsampling` par 2 lu
  depuis un `upsampling` par 3 du même parent). La position fractionnaire en donne le
  sens, mais l'exécution demande d'entrelacer ou de tamponner les deux régions. Faut-il
  l'implémenter, ou exiger ici la compatibilité et imposer le passage par le parent ?
- **[Q3]** Entrée d'un `upsampling` : maintien par défaut, ou bourrage de zéros comme
  dans `FIR20` ?
- **[Q4]** Les horloges $\mathbf{I}$, $\mathbf{B}$, $\mathbf{S}$ remplacent-elles la
  variabilité à terme, ou restent-elles une vue au-dessus de l'existant ?
- **[Q5]** Sorties qui *collectent* (`vectorize`/`serialize`, trames FFT,
  `interleave`) : le générateur de table en est déjà une. À prévoir dans les types dès
  maintenant ?
- **[Q6]** `switch(C0..Ck)` : horloges de cadences complémentaires. Faut-il une notion
  d'horloges *exclusives* pour partager l'état ou le code ?
- **[Q7]** Cadence quelconque ($r$ tantôt nul, tantôt supérieur à 1) : à conserver, ou
  à restreindre à la sélection et à la subdivision pures ?
- **[Q8]** Cadence définie sur $\mathbf{B}$ (ondemand piloté par un slider) : la région
  doit-elle sortir de la boucle d'échantillons ?
