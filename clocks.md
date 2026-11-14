# Un calcul d'horloges pour Faust

**[Spécification, brouillon v9 — 14 novembre 2026]**

Objet : la théorie des horloges qui servira de base à `ondemand`, `upsampling` et
`downsampling` sur la lignée `master-dev-certification`.

**Statut.** Décision du 13 novembre : on spécifie, on n'implémente pas. L'implémentation
ne commencera qu'après la bascule de `master-dev` sur la branche de certification. Le
but de la spécification est d'être simple, régulière, et de proposer les bonnes
abstractions.

Cette version réécrit le calcul autour de quatre idées : une seule construction
d'horloge, une seule relation entre horloges (le raffinement), une seule opération qui
change d'horloge (`On`), et une place pour l'horloge dans la signature algébrique. Les
notes **[D]** sont des décisions prises, **[P]** des propositions, **[Q]** des questions.

Sources : `spec.md` (ondemand v5), les documents Expressive E, les slides IFC-24, et
dans `faust-migration` : `FAUSTALGEBRA.md`, `LES-ALGEBRES-DE-TRANSFORMATION.md`,
`ATTRIBUTES.md`, `FIXPOINT-SPEC.md`, `LA-FORME-DE-CALCUL.md`.

## 1. Les horloges

Cette section ne parle que du temps. Les signaux n'arrivent qu'à la section 2.

### 1.1 Les instants

On se donne un ensemble $\mathbb{T}$ d'**instants**, totalement ordonné : de deux
instants distincts, l'un précède l'autre.

Les échantillons $0, 1, 2, \ldots$ sont des instants. Ce ne sont pas les seuls : il y a
d'autres instants entre deux échantillons successifs. On en aura besoin en 1.4.

### 1.2 Les horloges et leurs tops

Une **horloge** est un ensemble d'instants. Ses éléments sont ses **tops**.

Deux horloges sont données par l'hôte, on les dit **naturelles** :

| Horloge | Ses tops |
|---|---|
| $\mathbf{S}$ | les échantillons |
| $\mathbf{B}$ | les débuts de blocs : le premier échantillon de chaque appel de `compute` |

### 1.3 Comparer deux horloges : l'inclusion

Les horloges étant des ensembles, on les compare par l'inclusion. $H \subseteq H'$ dit
que tout top de $H$ est un top de $H'$ : $H$ est **plus rare**, $H'$ **plus fine**.

Par exemple $\mathbf{B} \subseteq \mathbf{S}$ : un début de bloc est un échantillon.

Deux horloges peuvent n'être incluses ni l'une dans l'autre. C'est le cas de « un
échantillon sur deux » et « un échantillon sur trois ».

### 1.4 Dériver une horloge d'une autre

On fabrique une horloge à partir d'une autre en disant, pour chaque top de la première,
combien de tops la seconde y place.

Soit $p$ une horloge, et $r$ une fonction qui donne à chaque top $\tau$ de $p$ un
entier $r(\tau) \ge 0$. L'horloge **dérivée** $p \triangleright r$ a $r(\tau)$ tops à
chaque top $\tau$ de $p$. On appelle $p$ son **parent** et $r$ sa **cadence**.

| $r(\tau)$ | Tops de $p \triangleright r$ à cet endroit |
|---|---|
| $0$ | aucun : le top $\tau$ est sauté |
| $1$ | un seul : $\tau$ lui-même |
| $n > 1$ | $n$ tops : $\tau$, puis $n - 1$ instants nouveaux, régulièrement répartis avant le top suivant de $p$ |

Le premier des tops placés en $\tau$ est toujours $\tau$ lui-même : c'est la
**convention « début »**. **[D]**

Un exemple, avec quatre tops de $p$ :

```
p        :   τ0          τ1          τ2          τ3
r        :   1           0           3           1
p ▷ r    :   τ0                      τ2  ·  ·    τ3
```

En $\tau_1$ rien n'est placé. En $\tau_2$ sont placés $\tau_2$ et deux instants
nouveaux, qui ne sont pas des tops de $p$.

Formellement, les instants nouveaux se notent $\tau \cdot q$, avec $q$ une fraction de
$[0, 1[$ qui dit à quelle proportion de l'intervalle entre $\tau$ et le top suivant ils
se trouvent, et $\tau \cdot 0 = \tau$ :

$$p \triangleright r = \{\tau \cdot \tfrac{j}{r(\tau)} \mid \tau \in p,\ 0 \le j < r(\tau)\}$$

### 1.5 Deux cas remarquables : sélection et subdivision

- Si $r$ ne vaut jamais plus de $1$, la dérivation ne fait que **sauter** des tops.
  C'est une **sélection** : $p \triangleright r \subseteq p$.
- Si $r$ vaut toujours au moins $1$, la dérivation ne fait qu'**ajouter** des tops.
  C'est une **subdivision** : $p \subseteq p \triangleright r$.

Dans l'exemple ci-dessus, $r$ fait les deux : l'horloge obtenue n'est ni incluse dans
$p$, ni plus fine que $p$.

### 1.6 Le raffinement

On dit que $c$ **raffine** $p$, et on note $p \le c$, quand $c$ s'obtient à partir de
$p$ par une subdivision, ou par plusieurs subdivisions successives.

Si $c$ raffine $p$, alors :

- $p \subseteq c$ : tous les tops de $p$ sont des tops de $c$ ;
- $p$ et $c$ ont le même premier top.

Le raffinement est plus exigeant que l'inclusion. Une sélection est incluse dans son
parent, mais elle ne le raffine pas, et son parent ne la raffine pas non plus.

Comme une horloge dérivée a un seul parent, les horloges qu'une horloge $c$ raffine se
rangent en file, de la plus rare à la plus fine. On note $\mathrm{Ch}(c)$ cette
**chaîne**, $c$ comprise.

### 1.7 Une seule horloge primitive

L'horloge des échantillons se dérive de celle des blocs : à chaque début de bloc, elle
place autant de tops que le bloc compte d'échantillons.

$$\mathbf{S} = \mathbf{B} \triangleright \mathit{count}$$

C'est une subdivision : $\mathbf{S}$ raffine $\mathbf{B}$. Toutes les horloges du
calcul s'obtiennent donc à partir de la seule horloge $\mathbf{B}$, par dérivation :

$$K ::= \mathbf{B} \;\mid\; K \triangleright r$$

Deux exemples de chaînes :

- pour $c = \mathbf{S} \triangleright 4$ (quatre tops par échantillon) :
  $\mathrm{Ch}(c) = \{\mathbf{B}, \mathbf{S}, c\}$ ;
- pour $c = \mathbf{S} \triangleright h$ avec $h \le 1$ (une sélection) :
  $\mathrm{Ch}(c) = \{c\}$.

## 2. Les signaux

### 2.1 Valeurs et signaux

Une **valeur** est un nombre. Elle est hors du temps : elle n'a pas d'horloge.

Un **signal** a une horloge, et une valeur à chacun des tops de cette horloge. Un
signal d'horloge $H$ est une fonction $H \to \mathbb{R}$. Entre deux tops, il n'est
pas défini.

Les entrées audio sont des signaux d'horloge $\mathbf{S}$, les sliders des signaux
d'horloge $\mathbf{B}$.

### 2.2 Lire un signal à un instant quelconque

On a souvent besoin de la valeur d'un signal à un instant qui n'est pas l'un de ses
tops. On prend alors sa valeur au dernier top passé.

La valeur d'un signal $x$ d'horloge $H$, **lue** à un instant $t$ :

$$x\lfloor t \rfloor = x(\max\{u \in H \mid u \le t\}) \qquad \text{et } 0 \text{ s'il n'y a pas encore eu de top}$$

Le « $\le$ » admet la lecture au top même.

### 2.3 Quand la lecture est sans perte

Lire un signal sur une horloge qui **contient** la sienne ne perd rien : on y retrouve
toutes ses valeurs, chacune maintenue jusqu'à la suivante. C'est le cas d'un slider lu
à chaque échantillon.

Lire un signal sur une horloge qui ne contient pas la sienne peut en perdre : les
valeurs prises entre deux tops du lecteur ne sont jamais vues.

**Cohérence.** Si $H \subseteq H'$, lire un signal d'horloge $H$ directement, ou le
lire d'abord sur $H'$ puis relire le résultat, donne la même chose.

### 2.4 La cadence est un signal

En 1.4 la cadence était une fonction quelconque. Dans un programme, c'est un signal :
la cadence $r$ de $p \triangleright r$ est un signal entier, positif ou nul, d'horloge
$p$. L'horloge et les signaux dépendent donc l'un de l'autre : un signal a une horloge,
et une horloge dérivée est construite avec un signal.

**[D] Égalité.** Deux horloges dérivées sont égales quand elles ont le même parent et
le même signal de cadence, comparé par identité d'arbre après mise en forme normale.

### 2.5 Les trois primitives du langage

| Primitive | Cadence | Nature | Fréquence vue à l'intérieur |
|---|---|---|---|
| `ondemand(P)(h)` | $h$, qui vaut $0$ ou $1$ | sélection | $\mathrm{SR}$ |
| `downsampling(P)(N)` | $1$ un top sur $N$, $0$ sinon | sélection | $\mathrm{SR} / N$ |
| `upsampling(P)(N)` | $N$ | subdivision | $N \cdot \mathrm{SR}$ |

Ce sont trois vues de la même construction. `downsampling(P)(N)` est un `ondemand`
dont la demande est un compteur modulo $N$ écrit sur l'horloge parente. La fréquence
d'échantillonnage appartient à la primitive, pas à l'horloge : elle est résolue à la
propagation.

### 2.6 Le temps différé

Le remplissage d'une table est le calcul d'un signal sur une horloge finie
$\mathbf{D}_n$, dont les $n$ tops précèdent tous l'échantillon $0$. C'est une seconde
horloge primitive. La table collecte les $n$ valeurs ; pour le temps réel c'est une
valeur.

Le temps-programme (compilation, initialisation, exécution) n'est pas une horloge de
signal : c'est la calculabilité, l'autre axe de `ATTRIBUTES.md`.

## 3. Les opérations

### 3.1 Trois sortes d'opérations

| Sorte | Exemples | Horloge du résultat |
|---|---|---|
| **sans mémoire** | arithmétique, `select2`, lecture et écriture de table | la plus fine de celles des arguments |
| **à horloge** | `Mem`, `Delay`, `Prefix`, `Fir`, `Iir`, `Irm`, `Waveform`, fonction étrangère sans argument | l'horloge $k$ qu'elle porte |
| **changement d'horloge** | `On` | l'horloge $k$ qu'elle porte |

Une opération est **à horloge** quand son résultat dépend du nombre de tops écoulés. Un
retard de 1 sur une horloge n'est pas un retard de 1 sur une autre :

```faust
ramp = +(1) ~ _;
process = ramp, ondemand(ramp);   // deux rampes distinctes
```

L'écriture de table n'en est pas une : réécrire la même valeur au même index est sans
effet, son état ne compte pas le temps. **[D]**

### 3.2 `On` : voir un signal d'une autre horloge

$\mathtt{On}(k, x)$ est le signal d'horloge $k$ qui vaut $x\lfloor t \rfloor$ à chaque
top $t$ de $k$. Appliqué à une valeur $v$, c'est le signal d'horloge $k$ qui vaut $v$ à
chaque top.

Selon les horloges, `On` échantillonne (vers une horloge plus rare), maintient (vers
une horloge qui contient celle de $x$), ou les deux.

### 3.3 Règles d'horloge

On note $\vdash s : k$ pour « $s$ est un signal d'horloge $k$ » et $\vdash s : \bot$
pour « $s$ est une valeur ». $\bot \le k$ pour tout $k$.

$$\frac{}{\vdash \mathit{nombre} : \bot} \qquad
\frac{}{\vdash \mathit{slider} : \mathbf{B}} \qquad
\frac{}{\vdash \mathit{input}_i : \mathbf{S}}$$

$$\frac{\vdash s_i : k_i \quad \text{les } k_i \text{ en chaîne}}{\vdash \star(s_1,\ldots,s_n) : \max_i k_i}\ (\textit{op})
\qquad
\frac{\vdash s_i : k_i \le k}{\vdash \mathtt{Delay}(k, s_1, s_2) : k}\ (\textit{mem})
\qquad
\frac{}{\vdash \mathtt{On}(k, s) : k}\ (\textit{on})$$

$$\frac{\vdash \mathrm{def}_j(W) : k_j \quad \text{les } k_j \text{ en chaîne}}{\vdash \mathtt{Proj}(i, W) : \max_j k_j}\ (\textit{proj})
\qquad
\frac{\vdash r : k \le p \quad r \in \mathbb{N}}{p \triangleright r \ \text{bien formée}}\ (\textit{clk})$$

- (*op*) et (*mem*) demandent des arguments dont l'horloge est raffinée par celle du
  résultat : ils sont lus sans perte. Seul `On` accepte un argument quelconque.
- C'est la règle de temporalité de `ATTRIBUTES.md` : la borne intrinsèque de
  l'opération, unie au join des arguments consultés.
- (*proj*) : les projections d'un groupe partagent une horloge, comme elles partagent
  une variabilité (« le groupe est couplé »). **[D]**
- (*clk*) : $r$ entier positif est une obligation de certification, prise sur la forme
  normale.

### 3.4 L'invariant de chaîne

**[D]** Dans le contexte lexical $c$, tout signal a une horloge de $\mathrm{Ch}(c)$.

Les prémisses de (*op*), (*mem*) et (*proj*) sont donc toujours satisfaites. Ce n'est
pas une contrainte pour l'utilisateur : la traduction établit l'invariant (section 4),
chaque transformation doit le préserver, et sa vérification est une obligation de
certification. Une violation est un défaut du compilateur.

### 3.5 Règles de valeur

Pour les attributs de valeur (nature, booléanité, intervalle), `On(k, x)` porte $x$ :

- quand $k$ est incluse dans l'horloge de $x$ (échantillonnage pur) : la valeur de $x$ ;
- sinon : la valeur de $x$ **unie à** $0$, la lecture avant le premier top.

Le maintien porte l'union avec la valeur initiale, exactement comme le retard dans
`FIXPOINT-SPEC.md` ($Y@n = Y \sqcup \alpha(0)$). Le raffinement, lui, n'ajoute jamais
de $0$ : une horloge et celles qui la raffinent ont le même premier top.

Conséquence à garder en tête : une valeur sortie d'un `ondemand` a $0$ dans son
intervalle, ce qui pèse sur la certification d'un retard ou d'un index qui en dépend.

L'horloge d'une opération à horloge n'entre dans aucun attribut de valeur.

## 4. La traduction des régions

Pour $P : n \to m$, dans le contexte $p$, avec $c = p \triangleright r$ :

$$[\![\mathtt{region}(P)]\!]_p(r, x_1..x_n) = (\mathtt{On}(p, \mathtt{On}(c, y_1)), \ldots)
\quad\text{où}\quad (y_1..y_m) = [\![P]\!]_c(\mathtt{On}(c, x_1), \ldots)$$

Toute feuille écrite dans $P$ (slider, entrée, signal extérieur capturé) est traduite
$\mathtt{On}(c, \mathit{feuille})$. La composition `~` écrit un `Mem(c, …)`. Les
nombres restent des valeurs.

**Une seule loi décide de ce qui reste** : $\mathtt{On}(k, x) = x$ quand $x$ est un
signal dont l'horloge est raffinée par $k$.

| | `ondemand`, `downsampling` | `upsampling` |
|---|---|---|
| entrée `On(c, x)` | reste : échantillonnage | s'efface : $p \le c$, maintien sur les sous-instants |
| sortie `On(c, y)` | s'efface si $y$ est un signal | s'efface si $y$ est un signal |
| sortie `On(p, …)` | reste : maintien entre deux demandes | reste : premier sous-échantillon |

La sortie est toujours un signal de l'horloge parente : c'est ce qui établit l'invariant
de chaîne, sans règle particulière. Deux régions voisines ne se lisent jamais
directement.

## 5. Lois

1. **Effacement** : $\mathtt{On}(k, x) = x$ si $x$ est un signal d'horloge $k' \le k$.
2. **Absorption** : $\mathtt{On}(k, \mathtt{On}(k', x)) = \mathtt{On}(k, x)$ si
   $k \subseteq k'$.
3. **Distribution** : $\mathtt{On}(k, \star(x_1, x_2)) = \star(\mathtt{On}(k, x_1), \mathtt{On}(k, x_2))$.
4. **Retards** : $\mathtt{Delay}(k, \mathtt{Delay}(k, x, a), b) = \mathtt{Delay}(k, x, a+b)$,
   à horloge égale seulement.
5. **Retard vu d'une sélection** : pour $c \subseteq p$ et $x$ d'horloge $c$,
   $\mathtt{On}(c, \mathtt{Mem}(p, \mathtt{On}(p, x))) = \mathtt{Mem}(c, x)$.
6. **Composition** : $(p \triangleright h_1) \triangleright h_0 = p \triangleright (h_1 \cdot h_0)$
   pour des cadences booléennes. C'est $h_0 \otimes h_1$ de la spec v5.
7. **Cas dégénérés** : $p \triangleright 1 = p$ ; $p \triangleright 0$ est l'horloge
   vide, dont tous les signaux se lisent $0$.

La fusion `ondemand(P)(h) : ondemand(Q)(h)` $=$ `ondemand(P:Q)(h)` découle de la loi 2
et de l'égalité structurelle. Elle est fausse pour un `upsampling`.

**[P] Forme canonique** : la loi 3 fait remonter `On` vers les consommateurs.

## 6. Exemples

On note $c = \mathbf{S} \triangleright h$. Les codes sont ceux que les règles
désignent ; ils n'ont pas été produits par un compilateur.

**Sample and hold.** `ondemand(_)` donne $\mathtt{On}(\mathbf{S}, \mathtt{On}(c, x))$.

```c
if (h) { fOn0 = input1[i]; }
output0[i] = fOn0;
```

**Bruit sous-échantillonné.** `ba.beat(100) : ondemand(no.noise)`. Le générateur est un
groupe $V$ de définition `Mem(c, Proj(0,V)) * 1103515245 + 12345`, d'horloge $c$. La
sortie est $\mathtt{On}(\mathbf{S}, \mathtt{Proj}(0,V) \cdot 4{,}65\mathrm{e}{-10})$. Le
code est celui des slides IFC-24.

**Ondemand imbriqués.** `ondemand(ondemand(P))` : par la loi 6, une seule horloge de
cadence $h_1 \cdot h_0$.

**Récursion à travers la frontière.**
`process(h) = y letrec { 'y = ondemand(+(1))(h, y); };` Par la loi 5 l'état passe dans
la région : `if (h) { iRec0 = iRec0 + 1; }`.

**Upsampling et filtre.** `upsampling(+ ~ *(0.5))` : $c = \mathbf{S} \triangleright N$
raffine $\mathbf{S}$, l'entrée s'efface, la sortie est $\mathtt{On}(\mathbf{S}, \mathtt{Proj}(0,W))$.

```c
for (int j = 0; j < N; j++) {
    fRec0[0] = input1[i] + 0.5f * fRec0[1];
    if (j == 0) { fOn0 = fRec0[0]; }
    fRec0[1] = fRec0[0];
}
output0[i] = fOn0;
```

**Constante.** `ondemand(1)` donne $\mathtt{On}(\mathbf{S}, \mathtt{On}(c, 1))$ : $0$
jusqu'à la première demande, puis $1$. C'est la sémantique de la spec v5.

## 7. La place dans l'approche algébrique

### 7.1 L'horloge dans la signature

L'arbre de signaux est l'algèbre initiale de la signature (`FAUSTALGEBRA.md`). Si
l'arbre portait une horloge que la signature ignore, une transformation qui passe par
`Delay(x, d)` rebâtirait un retard sans horloge : c'est la lacune de fidélité décrite
dans `LES-ALGEBRES-DE-TRANSFORMATION.md`. L'horloge fait partie de la dénotation d'un
retard ; sa place est dans la signature.

**[P]** L'horloge est un opérande, pas une donnée : elle contient un signal, la
cadence, que chaque interprétation interprète et chaque transformation transforme.

```
Clock(parent, rate)                    l'horloge dérivée ; ClockBlock, ClockSample les naturelles
On(clk, x)
Mem(clk, x)   Delay(clk, x, d)   Prefix(clk, x0, x)
Fir(clk, x, coefs)   Iir(clk, x, coefs)   Irm(clk, x, c)   Waveform(clk, w)
```

| Algèbre | Valeur d'une horloge |
|---|---|
| arbres | le terme d'horloge |
| horloges | l'horloge ; une opération à horloge vaut son horloge |
| intervalles | les bornes de la cadence, pour convertir le temps local en temps parent |
| nature, booléanité | rien |

**[Q] Une ou deux sortes.** Soit l'horloge est un `T` comme les étiquettes, soit la
signature a deux paramètres, `FaustAlgebra<T, K>`. Avec deux sortes, confondre un
signal et une horloge est une erreur de compilation, et chaque algèbre choisit son
`K` ; en contrepartie toutes les algèbres existantes changent de forme. Non tranché.

### 7.2 Les deux formes

`LA-FORME-DE-CALCUL.md` distingue la forme normale, où l'on certifie, de la forme de
calcul, qui porte les décisions comme données.

- **Forme normale.** L'horloge est l'opérande ci-dessus. La certification y prouve,
  pour chaque horloge dérivée, que la cadence est un entier positif et borné.
- **Forme de calcul.** La cadence est une décision : `Clock(parent, rate, rmin, rmax)`
  porte ses bornes certifiées, comme `Delay(L, d, dmin, dmax)`. La génération y lit la
  forme du code, sans relire d'intervalle : $r_{max} \le 1$ donne un `if`,
  $r_{min} \ge 1$ une boucle. L'horloge se porte sur la ligne, `DelayLine(clk, x, n)` ;
  ses lectures et les prises d'un `Fir` n'en ont pas besoin.
- **Cône des décisions.** La cadence d'une horloge atteint une décision mémoire (le
  nombre d'exécutions d'une région). Elle est dans le cône et n'est jamais réécrite par
  la forme de calcul.
- **Typage léger.** L'horloge y remplace la cadence (constante, bloc, échantillon),
  dont elle est la généralisation.

### 7.3 Le point fixe

L'horloge est un attribut exact. Sa graine pour une variable récursive est le bas
($\bot$), et non une valeur pessimiste comme `kSamp` pour la variabilité : un groupe
écrit dans un `ondemand` n'est pas sur l'horloge échantillon. Le calcul monte tout
seul, parce que toute boucle traverse une opération à horloge. **[Q]** : garder le bas,
ou fournir à l'itérateur l'horloge du contexte.

## 8. Où le code est exécuté

L'horloge d'un signal dit quand sa valeur peut changer. Le compilateur choisit en plus
où il émet le calcul.

- Une opération à horloge s'exécute sur son horloge, sans choix : un écho inaudible
  vieillit quand même. La règle `isConditionBoundary` de la branche en devient une
  conséquence.
- Une opération sans mémoire peut s'exécuter sur toute horloge qui contient les
  instants où elle est lue (loi de cohérence). Vers une horloge plus rare, c'est
  l'appel par nécessité ; vers une horloge moins fine, la sortie des invariants de
  boucle.

Une région d'horloge est un nœud du graphe de son parent. Chaque horloge a son index de
temps. Lire un signal hors de son horloge coûte une variable qui garde sa dernière
valeur.

## 9. État de l'implémentation

Rien n'est implémenté au-delà de deux étapes sans effet sur le code généré, sur la
branche `ccr-faae028d-7grw0l` de `grame-cncm/faust`, au-dessus de
`master-dev-certification-4` :

- **Étape 0** (`c3a3f794a`) : `ClockAlgebra` restreinte aux horloges naturelles,
  calculée à côté de la variabilité, et un test de concordance sous
  `FAUST_CHECK_CLOCKS`. Aucune divergence sur la suite d'impulsions (103 programmes,
  quatre jeux d'options) ni sur les exemples (259 programmes, environ 206 000 signaux).
  Code généré identique à la référence sur 2 678 compilations.
- **Étape 1** (`dc1d83c1d`, `314a6dc05`) : le front-end des trois primitives (mots
  réservés, boîtes, typage, impression, schéma). La propagation les refuse. Le parser
  est régénéré par bison 3.8.2 au lieu de 2.3, dans un commit séparé.

La projection de l'horloge sur la variabilité : une valeur donne `kKonst`,
$\mathbf{B}$ donne `kBlock`, $\mathbf{S}$ et toute horloge dérivée donnent `kSamp`.

## 10. Décisions et questions

**Prises**

- Convention « début » pour les sous-instants.
- Égalité structurelle des horloges.
- La sortie d'une région est un signal de l'horloge parente.
- Maintien en entrée d'`upsampling` ; un bourrage de zéros s'écrit dans la région.
- L'écriture de table n'est pas une opération à horloge.
- Les projections d'un groupe partagent une horloge.
- L'horloge est calculée à côté de la variabilité, avec un test de concordance.
- Une branche d'horloge sur chaque opération à horloge, y compris hors région.
- Spécifier d'abord ; implémenter après la bascule de `master-dev`.

**En attente**

- Une ou deux sortes dans la signature (7.1).
- La graine des variables récursives (7.3).

**Ouvertes**

- **[Q1]** Un maintien à valeur initiale explicite, qui serait à `On` ce que `Prefix`
  est à `Mem`, pour ne pas forcer $0$ dans l'intervalle d'une sortie de région.
- **[Q2]** Les sorties qui collectent plusieurs valeurs (`vectorize`, trames FFT,
  `interleave`). Le remplissage de table en est une.
- **[Q3]** `switch(C0..Ck)` : des sélections de cadences complémentaires.
- **[Q4]** Une cadence tantôt nulle, tantôt supérieure à 1. Le calcul la définit (ni
  sélection ni subdivision) ; faut-il l'accepter dans le langage ?
- **[Q5]** La valeur d'une horloge dans le domaine des intervalles, et la conversion de
  l'horizon entre temps local et temps parent.
- **[Q6]** La vectorisation des régions de cadence constante.
