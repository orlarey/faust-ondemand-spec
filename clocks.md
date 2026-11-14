# Un calcul d'horloges pour Faust

**[Spécification, brouillon v10 — 14 novembre 2026]**

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

Cette section ne parle que du temps. Les signaux n'arrivent qu'à la section 2. Tout y
est construit sur $\mathbb{N}$ et $\mathbb{Q}$.

### 1.1 Les dates

Une **date** est un nombre rationnel positif ou nul, un élément de $\mathbb{Q}^+$.
L'unité est l'échantillon : la date $n \in \mathbb{N}$ est celle de l'échantillon $n$,
et $2{,}5$ est à mi-chemin entre les échantillons $2$ et $3$.

Les dates sont ordonnées comme les nombres. On n'a pas besoin des réels : toutes les
dates du calcul s'obtiennent en divisant des entiers.

### 1.2 Les tops

Un **top** est un couple $(d, \delta)$ formé d'une date $d \in \mathbb{Q}^+$ et d'une
**durée** $\delta \in \mathbb{Q}$, $\delta > 0$. Il occupe l'intervalle de dates
$[d,\ d + \delta[$ : il commence à $d$ et dure $\delta$.

Par exemple $(3, 1)$ est l'échantillon $3$ : il commence à la date $3$ et dure un
échantillon.

### 1.3 Les horloges

Une **horloge** est un ensemble de tops dont les intervalles sont deux à deux
disjoints. On peut donc ranger ses tops par dates croissantes : premier top, deuxième
top, etc.

Deux horloges sont données par l'hôte :

- l'horloge des **échantillons**, $\mathbf{S} = \{(n, 1) \mid n \in \mathbb{N}\}$ ;
- l'horloge des **blocs**. Si les appels successifs de `compute` commencent aux
  échantillons $b_0 = 0 < b_1 < b_2 < \ldots$, alors
  $\mathbf{B} = \{(b_k,\ b_{k+1} - b_k) \mid k \in \mathbb{N}\}$ : un top par bloc, qui
  commence avec le bloc et dure autant que lui.

Avec des blocs de 64 échantillons, $\mathbf{B} = \{(0, 64), (64, 64), (128, 64), \ldots\}$.

### 1.4 Dériver une horloge d'une autre

On fabrique une horloge à partir d'une autre en découpant chacun de ses tops en parts
égales.

Soit $p$ une horloge, et $r : p \to \mathbb{N}$ une fonction qui donne à chaque top de
$p$ un entier. L'horloge **dérivée** $p \triangleright r$ remplace chaque top
$\tau = (d, \delta)$ de $p$ par $r(\tau)$ tops de durée $\delta / r(\tau)$, mis bout à
bout à partir de $d$ :

$$p \triangleright r = \left\{ \left(d + j \cdot \tfrac{\delta}{r(\tau)},\ \tfrac{\delta}{r(\tau)}\right) \;\middle|\; \tau = (d, \delta) \in p,\ 0 \le j < r(\tau) \right\}$$

On appelle $p$ le **parent** et $r$ la **cadence**.

| $r(\tau)$ | Ce que devient le top $\tau = (d, \delta)$ |
|---|---|
| $0$ | rien : le top est supprimé |
| $1$ | lui-même |
| $n > 1$ | $n$ tops de durée $\delta / n$, aux dates $d,\ d + \delta/n,\ \ldots$ |

Le premier des tops issus de $\tau$ commence toujours à la date de $\tau$. **[D]**

Un exemple, sur quatre échantillons :

```
p        :  (0,1)        (1,1)        (2,1)                    (3,1)
r        :   1            0            3                         1
p ▷ r    :  (0,1)                     (2,⅓) (2⅓,⅓) (2⅔,⅓)      (3,1)
```

L'échantillon $1$ est supprimé. L'échantillon $2$ est découpé en trois tops, qui
restent tous à l'intérieur de l'intervalle $[2, 3[$.

### 1.5 Deux cas remarquables : sélection et subdivision

- Si $r$ ne vaut jamais plus de $1$, la dérivation ne fait que **supprimer** des tops.
  C'est une **sélection**, et $p \triangleright r \subseteq p$ : c'est un sous-ensemble
  de $p$.
- Si $r$ vaut toujours au moins $1$, la dérivation ne fait que **découper** des tops.
  C'est une **subdivision**.

Dans l'exemple ci-dessus, $r$ fait les deux.

### 1.6 Le raffinement

On dit que $c$ **raffine** $p$, et on note $p \le c$, quand $c$ s'obtient à partir de
$p$ par une subdivision, ou par plusieurs subdivisions successives.

Si $c$ raffine $p$, alors :

- chaque top de $p$ est exactement recouvert par des tops de $c$ ;
- toute date où commence un top de $p$ est une date où commence un top de $c$ ;
- $p$ et $c$ commencent à la même date.

Une sélection ne raffine pas son parent, et son parent ne la raffine pas.

Une horloge dérivée a un seul parent. Les horloges qu'une horloge $c$ raffine se
rangent donc en file, de la moins fine à la plus fine. On note $\mathrm{Ch}(c)$ cette
**chaîne**, $c$ comprise.

### 1.7 Une seule horloge primitive

L'horloge des échantillons se dérive de celle des blocs. Prenons pour cadence la
longueur du bloc, $\mathit{count}(b_k,\ b_{k+1} - b_k) = b_{k+1} - b_k$ : chaque bloc
est découpé en tops de durée $1$. Donc

$$\mathbf{S} = \mathbf{B} \triangleright \mathit{count}$$

C'est une subdivision : $\mathbf{S}$ raffine $\mathbf{B}$. Toutes les horloges du
calcul s'obtiennent ainsi à partir de la seule horloge $\mathbf{B}$, par dérivation :

$$K ::= \mathbf{B} \;\mid\; K \triangleright r$$

Deux exemples de chaînes :

- pour $c = \mathbf{S} \triangleright 4$ (chaque échantillon découpé en quatre) :
  $\mathrm{Ch}(c) = \{\mathbf{B}, \mathbf{S}, c\}$ ;
- pour $c = \mathbf{S} \triangleright h$ avec $h \le 1$ (une sélection) :
  $\mathrm{Ch}(c) = \{c\}$.

## 2. Les signaux

### 2.1 Valeurs et signaux

Une **valeur** est un nombre, un élément de $\mathbb{R}$. Elle est hors du temps.

Un **signal** d'horloge $H$ est une fonction $x : H \to \mathbb{R}$ : il a une valeur
$x(\tau)$ à chaque top $\tau$ de son horloge, et il n'est défini nulle part ailleurs.

Les entrées audio sont des signaux d'horloge $\mathbf{S}$, les sliders des signaux
d'horloge $\mathbf{B}$.

### 2.2 Lire un signal à une date quelconque

On a souvent besoin de la valeur d'un signal à une date où aucun de ses tops ne
commence. On prend alors sa valeur au dernier top commencé.

La valeur d'un signal $x$ d'horloge $H$, **lue** à la date $t \in \mathbb{Q}^+$ :

$$x\lfloor t \rfloor = \begin{cases}
x(d, \delta) & \text{où } (d, \delta) \text{ est le top de } H \text{ de plus grande date } d \le t \\
0 & \text{si aucun top de } H \text{ n'a commencé à la date } t
\end{cases}$$

Seule la date des tops compte pour la lecture, pas leur durée : la valeur est
maintenue jusqu'au top suivant, même s'il est lointain.

### 2.3 Quand la lecture est sans perte

Soit $x$ un signal d'horloge $H$, lu à chaque top d'une horloge $H'$.

- Si toute date où commence un top de $H$ est une date où commence un top de $H'$, la
  lecture ne perd rien : chaque valeur de $x$ est vue, et maintenue jusqu'à la
  suivante. C'est le cas quand $H'$ raffine $H$ (un slider lu à chaque échantillon), et
  aussi quand $H$ est une sélection de $H'$.
- Sinon elle peut en perdre : une valeur de $x$ remplacée avant le top suivant de $H'$
  n'est jamais vue.

**Cohérence.** Dans le premier cas, lire $x$ directement à une date, ou lire d'abord
$x$ sur $H'$ puis relire le résultat à cette date, donne la même chose.

### 2.4 La cadence est un signal

En 1.4 la cadence était une fonction quelconque de $p$ dans $\mathbb{N}$. C'est
exactement ce qu'est un signal entier d'horloge $p$. Dans un programme, la cadence de
$p \triangleright r$ est un tel signal. Les deux notions dépendent donc l'une de
l'autre : un signal a une horloge, et une horloge dérivée est construite avec un
signal.

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

Le remplissage d'une table de taille $n$ est le calcul d'un signal sur une horloge
finie de $n$ tops, placés avant la date $0$ : c'est la seule horloge dont les dates
sont négatives, et une seconde horloge primitive. La table collecte les $n$ valeurs ;
pour le temps réel c'est une valeur.

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

$\mathtt{On}(k, x)$ est le signal d'horloge $k$ dont la valeur, à chaque top de $k$,
est $x$ lu à la date de ce top : $\mathtt{On}(k, x)(d, \delta) = x\lfloor d \rfloor$.
Appliqué à une valeur $v$, c'est le signal d'horloge $k$ qui vaut $v$ à chaque top.

Selon les horloges, `On` échantillonne (quand $k$ est une sélection de l'horloge de
$x$), maintient (quand $k$ la raffine), ou les deux.

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

- quand aucun top de $k$ ne peut précéder le premier top de $x$ : la valeur de $x$.
  C'est le cas si $k$ est une sélection de l'horloge de $x$, si elle la raffine, ou si
  elle est raffinée par elle ;
- sinon : la valeur de $x$ **unie à** $0$, ce que rend la lecture tant que $x$ n'a pas
  commencé.

Le maintien porte l'union avec la valeur initiale, exactement comme le retard dans
`FIXPOINT-SPEC.md` ($Y@n = Y \sqcup \alpha(0)$). Le raffinement, lui, n'ajoute jamais
de $0$ : une horloge et celles qui la raffinent commencent à la même date.

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
| entrée `On(c, x)` | reste : échantillonnage | s'efface : $p \le c$, maintien sur les tops issus du même top parent |
| sortie `On(c, y)` | s'efface si $y$ est un signal | s'efface si $y$ est un signal |
| sortie `On(p, …)` | reste : maintien entre deux demandes | reste : premier sous-échantillon |

La sortie est toujours un signal de l'horloge parente : c'est ce qui établit l'invariant
de chaîne, sans règle particulière. Deux régions voisines ne se lisent jamais
directement.

## 5. Lois

1. **Effacement** : $\mathtt{On}(k, x) = x$ si $x$ est un signal d'horloge $k' \le k$.
2. **Absorption** : $\mathtt{On}(k, \mathtt{On}(k', x)) = \mathtt{On}(k, x)$ si
   $k$ est une sélection de $k'$, ou si $k'$ raffine $k$.
3. **Distribution** : $\mathtt{On}(k, \star(x_1, x_2)) = \star(\mathtt{On}(k, x_1), \mathtt{On}(k, x_2))$.
4. **Retards** : $\mathtt{Delay}(k, \mathtt{Delay}(k, x, a), b) = \mathtt{Delay}(k, x, a+b)$,
   à horloge égale seulement.
5. **Retard vu d'une sélection** : pour $c$ sélection de $p$ et $x$ d'horloge $c$,
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
  dates où elle est lue (loi de cohérence). Vers une horloge plus rare, c'est
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

- Un top découpé commence à la date de son parent, et ses parts restent dans sa durée.
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
