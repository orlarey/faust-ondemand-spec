# Un calcul d'horloges pour Faust

**[Spécification, brouillon v8 — 13 novembre 2026]**

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

## 1. Le calcul en une page

1. Le temps est un ensemble totalement ordonné d'**instants**. Une **horloge** est un
   ensemble d'instants, ses **tops**. Un **signal** a une horloge et une valeur à chacun
   de ses tops.
2. Un signal se **lit** à un instant quelconque : sa valeur à son dernier top, et $0$
   avant le premier.
3. Il y a une horloge primitive, celle des blocs, et **une construction** :
   $p \triangleright r$ a $r(\tau)$ tops à chaque top $\tau$ de $p$.
4. Il y a **une relation** : $c$ *raffine* $p$ quand $c$ s'obtient de $p$ en ajoutant
   des tops. Un signal se lit sans perte sur toute horloge qui raffine la sienne.
5. Il y a **une opération** qui change d'horloge : `On(c, x)`, « $x$ vu de $c$ ».
6. Les opérations qui **comptent le temps** (retards, filtres) portent leur horloge.
   Les autres ont l'horloge la plus fine de leurs arguments.
7. Dans un contexte, les horloges des signaux forment toujours une **chaîne**.

## 2. Le temps

### 2.1 Instants, horloges, signaux

$\mathbb{T}$ est l'ensemble des instants, totalement ordonné. Une horloge est une
partie de $\mathbb{T}$. Un signal d'horloge $H$ est une fonction $H \to \mathbb{R}$.

Une **valeur** (un nombre, une constante calculée à l'initialisation) n'est pas un
signal : elle est hors du temps et n'a pas d'horloge.

### 2.2 La lecture

La valeur d'un signal $x$ d'horloge $H$, lue à un instant $t$ quelconque :

$$x\lfloor t \rfloor = x(\max\{u \in H \mid u \le t\}) \qquad \text{et } 0 \text{ s'il n'y a pas encore eu de top}$$

C'est l'instant le plus proche qui respecte la causalité. Le « $\le$ » admet la lecture
au même instant : un cycle de dépendances doit contenir un retard.

**Cohérence.** Si $H \subseteq H'$, lire $x$ directement ou en passant par $H'$ donne
le même résultat. Passer par une horloge qui contient la sienne est neutre ; passer par
une autre peut perdre de l'information.

## 3. Les horloges

### 3.1 Une primitive, une construction

$$K ::= \mathbf{B} \;\mid\; K \triangleright r$$

- $\mathbf{B}$ est l'horloge des **blocs** : un top au début de chaque appel de
  `compute`. Elle est donnée par l'hôte.
- $p \triangleright r$ est l'horloge **dérivée** de $p$ par le signal de **cadence**
  $r$, entier positif ou nul, d'horloge $p$. Elle a $r(\tau)$ tops à chaque top $\tau$
  de $p$ :

$$p \triangleright r = \{\tau \cdot \tfrac{j}{r(\tau)} \mid \tau \in p,\ 0 \le j < r(\tau)\}$$

L'instant $\tau \cdot q$ est situé entre $\tau$ et le top suivant de $p$, à la
proportion $q$. **[D] Convention « début »** : $\tau \cdot 0 = \tau$, le premier
sous-instant est l'instant parent.

L'horloge des **échantillons** n'est pas primitive : $\mathbf{S} = \mathbf{B} \triangleright \mathit{count}$,
où $\mathit{count}$ est la taille du bloc.

**[D] Égalité.** Deux horloges sont égales si elles ont même parent et même signal de
cadence, comparé par identité d'arbre après mise en forme normale.

### 3.2 Le raffinement

$c$ **raffine** $p$, noté $p \le c$, quand $c = p \triangleright r$ avec $r \ge 1$, ou
par transitivité. Alors $p \subseteq c$ (par la convention « début »), et les deux
horloges ont le même premier top.

- $r \ge 1$ : **subdivision**, $c$ raffine $p$.
- $r \le 1$ : **sélection**, $c \subseteq p$, mais $c$ ne raffine pas $p$ et $p$ ne
  raffine pas $c$.

Chaque horloge a un seul parent : les horloges que $c$ raffine forment une **chaîne**,
notée $\mathrm{Ch}(c)$. Par exemple
$\mathrm{Ch}(\mathbf{S} \triangleright 4) = \{\mathbf{B}, \mathbf{S}, \mathbf{S} \triangleright 4\}$
et $\mathrm{Ch}(\mathbf{S} \triangleright h) = \{\mathbf{S} \triangleright h\}$ pour
une sélection.

Le raffinement est la seule relation du calcul. Il est décidé par la forme du terme et
par la preuve $r \ge 1$, jamais en comparant deux horloges quelconques.

### 3.3 Les trois primitives du langage

| Primitive | Cadence | Fréquence vue à l'intérieur |
|---|---|---|
| `ondemand(P)(h)` | $h$ | $\mathrm{SR}$ |
| `upsampling(P)(N)` | $N$ | $N \cdot \mathrm{SR}$ |
| `downsampling(P)(N)` | un top sur $N$ | $\mathrm{SR} / N$ |

Ce sont trois vues de la même construction. `downsampling(P)(N)` est un `ondemand`
dont la demande est un compteur modulo $N$ écrit sur l'horloge parente. La fréquence
d'échantillonnage appartient à la primitive, pas à l'horloge : elle est résolue à la
propagation.

### 3.4 Le temps différé

Le remplissage d'une table est le calcul d'un signal sur une horloge finie
$\mathbf{D}_n$, dont les $n$ tops précèdent tous l'instant $0$. C'est une seconde
racine. La table collecte les $n$ valeurs ; pour le temps réel c'est une valeur.

Le temps-programme (compilation, initialisation, exécution) n'est pas une horloge de
signal : c'est la calculabilité, l'autre axe de `ATTRIBUTES.md`.

## 4. Les opérations

### 4.1 Trois sortes d'opérations

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

### 4.2 `On` : voir un signal d'une autre horloge

$\mathtt{On}(k, x)$ est le signal d'horloge $k$ qui vaut $x\lfloor t \rfloor$ à chaque
top $t$ de $k$. Appliqué à une valeur $v$, c'est le signal d'horloge $k$ qui vaut $v$ à
chaque top.

Selon les horloges, `On` échantillonne (vers une horloge plus rare), maintient (vers
une horloge qui contient celle de $x$), ou les deux.

### 4.3 Règles d'horloge

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

### 4.4 L'invariant de chaîne

**[D]** Dans le contexte lexical $c$, tout signal a une horloge de $\mathrm{Ch}(c)$.

Les prémisses de (*op*), (*mem*) et (*proj*) sont donc toujours satisfaites. Ce n'est
pas une contrainte pour l'utilisateur : la traduction établit l'invariant (section 5),
chaque transformation doit le préserver, et sa vérification est une obligation de
certification. Une violation est un défaut du compilateur.

### 4.5 Règles de valeur

Pour les attributs de valeur (nature, booléanité, intervalle), `On(k, x)` porte $x$ :

- quand $k$ est incluse dans l'horloge de $x$ (échantillonnage pur) : la valeur de $x$ ;
- sinon : la valeur de $x$ **unie à** $0$, la lecture avant le premier top.

Le maintien porte l'union avec la valeur initiale, exactement comme le retard dans
`FIXPOINT-SPEC.md` ($Y@n = Y \sqcup \alpha(0)$). Le raffinement, lui, n'ajoute jamais
de $0$ : une horloge et celles qui la raffinent ont le même premier top.

Conséquence à garder en tête : une valeur sortie d'un `ondemand` a $0$ dans son
intervalle, ce qui pèse sur la certification d'un retard ou d'un index qui en dépend.

L'horloge d'une opération à horloge n'entre dans aucun attribut de valeur.

## 5. La traduction des régions

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

## 6. Lois

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

## 7. Exemples

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

## 8. La place dans l'approche algébrique

### 8.1 L'horloge dans la signature

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

### 8.2 Les deux formes

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

### 8.3 Le point fixe

L'horloge est un attribut exact. Sa graine pour une variable récursive est le bas
($\bot$), et non une valeur pessimiste comme `kSamp` pour la variabilité : un groupe
écrit dans un `ondemand` n'est pas sur l'horloge échantillon. Le calcul monte tout
seul, parce que toute boucle traverse une opération à horloge. **[Q]** : garder le bas,
ou fournir à l'itérateur l'horloge du contexte.

## 9. Où le code est exécuté

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

## 10. État de l'implémentation

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

## 11. Décisions et questions

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

- Une ou deux sortes dans la signature (8.1).
- La graine des variables récursives (8.3).

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
