# _On-demand_ computations in Faust

**[YO, Preliminary draft v4]**

## Introduction

There are requests for using Faust in a more _composition-oriented_ way. For that purpose, it has been suggested to introduce _on-demand_ computations. In this model, computations are not performed on a sample-by-sample basis, as is normally the case with Faust, but only on request. Conceptually, these requests are propagated backwards, starting from the output of the expression and going back to the inputs.

The challenge is to introduce _on-demand_ computations while keeping the simple and well-defined _signal processor_ semantics of Faust. In this note we propose a new $\mathtt{ondemand}(P)\rightarrow P'$ primitive that transforms a signal processor $P$ into an _on-demand_ signal processor $P'$, and we define its semantics. As we will see, this semantics can be expressed using the regular Faust semantics, but applied to _downsampled_ signals.

## Semantics of Faust Expressions

Before describing the particular semantics of $\mathtt{ondemand}()$, let's take a look at the semantics of Faust in general. Faust semantics is based on _signals_ and _signal processors_. A _signal_ is a function of time and a _signal processor_ is a function of signals. A Faust program describes a _signal processor and programming in Faust is essentially combining _signal processors_ together, for example using composition operators like $\mathtt{:}$ or $\mathtt{\sim}$. 

### Time

Time in Faust is discrete and it is represented by $\mathbb{Z}$. All computations start at time $0$, but negative $times are possible in order to take delay operations into account .

### Signals

A _signal_ $s$ is a function of time $s:\mathbb{Z}\rightarrow\mathbb{R}$. Actually Faust considers two types of signals: _integer signals_ $(s:\mathbb{Z}\rightarrow\mathbb{Z})$ and _floating point signals_ ($s:\mathbb{Z}\rightarrow\mathbb{Q}$) but this distinction doesn't matter here. The value of a signal $s$ at time $t$ is written $s(t)$. 

The set of all possible signals in Faust is $\mathbb{S}\subset\mathbb{Z}\rightarrow\mathbb{R}$. The set $\mathbb{S}$  is a subset of $\mathbb{Z}\rightarrow\mathbb{R}$ because the value of any Faust signal $s$ at a negative time is always $0$: $\forall s\in\mathbb{S},s(t<0)=0$. In operational terms this corresponds to initialising all delay lines with $0$s.

### Tuples

A group of $n$ signals (a $n$-tuple of signals) is written $(s_{1},\ldots,s_{n})\in \mathbb{S}^{n}$. The *empty tuple*, single element of $\mathbb{S}^{0}$ is notated  $()$.

### Signal Processors

A *signal processors* $P:\mathbb{S}^{n}\rightarrow\mathbb{S}^{m}$, is a function that maps a $n$-tuple of signals to a $m$-tuple of signals . The set $\mathbb{P}=\bigcup_{n,m}\mathbb{S}^{n}\rightarrow\mathbb{S}^{m}$ is the set of all possible signal processors.

### Composition operators

The five composition operators of Faust ($<: \ :\ :>\ ,\ \sim$) are all binary operations on signal processors: $\mathbb{P}\times\mathbb{P}\rightarrow\mathbb{P}$.

### Semantic Brackets

In order to distinguish a Faust expression from its _meaning_ as a signal processor, we use the semantic brackets notation $[\![\ ]\!]$. For example $[\![+]\!]$ represents the *meaning* of Faust expression $+$ , a signal processor with the following type and definition: 
$$
\begin{align}
	[\![+]\!]&: \mathbb{S}^2\rightarrow\mathbb{S}^1 \\
[\![+]\!](x,y) &= \lambda t.(x(t)+y(t))	
\end{align}
$$
Numbers are also signal processors. The *meaning* of the Faust expression $1$ is the following: 

$$
\begin{align}
	[\![1]\!]&: \mathbb{S}^0\rightarrow\mathbb{S}^1 \\
[\![1]\!]() &= \lambda t.\left\{ \begin{array}{lr}
                0  &(t < 0)\\
                1  &(t \ge 0)
              \end{array}\right.

\end{align}
$$


## The $\mathtt{ondemand}(P)$ primitive

The vast majority of Faust primitives, like $+$ or $\mathtt{enable}$, are operations on *signals*. The $\mathtt{ondemand}$ primitive is very different. It is an operation on *signal processors* of type $\mathbb{P}\rightarrow\mathbb{P}$. It transforms a signal processor $P$ into an on-demand version, as illustrated in the figure below:

![ondemand0](images/ondemand0.png)

If $P$ has $n$ inputs and $m$ outputs, then $\mathtt{ondemand}(P)$ has $n+1$ inputs and $m$ outputs. The additional input of $\mathtt{ondemand}(P)$ is a clock signal $h$ that indicates by a $1$ when there is a computation demand, and by $0$ otherwise. In other words, $h(t)=1$ means that there is a computation demand at time $t$.
$$
\frac{P:n\rightarrow m}{\mathtt{ondemand}(P):1+n\rightarrow m}
$$

### The clock signal $h$

From a clock signal $h$ we can derive a signal $h^*$ that indicates the time of each demand. For example if $h=1,0,0,1,0,0,0,1,0\ldots$ then $h^*=0,3,7,\ldots$ indicating that the first demand is at time $0$, the second one at time $3$, the third one at time $7$, etc. We have 
$$
\begin{split}
h^*(0) &= \min \{t'|(h(t')=1)\} \\
h^*(t) &= \min \{t'|(h(t')=1) \and (t'>h^*(t-1))\}
\end{split}
$$


We also derive another signal $h^+$ that _counts_ the number of demands:
$$
h^+(t) = \sum_{i=0}^t h(i)
$$
For the same $h=1,0,0,1,0,0,0,1,0\ldots$ we have $h^+=1,1,1,2,2,2,2,3,3,\ldots$

Now that we have defined the clocks signals $h$ and $h^*$, we can introduce the _downsampling_ and _upsampling_  operations needed to express the _on-demand_ semantics. 

### Downsampling

The downsamplig operation is notated $\downarrow h$. For a signal $x$, the downsampled signal $x\downarrow h$ is defined as:
$$
x\downarrow h = \lambda t.x(h^*(t))
$$
For example if $x=0.0, -0.1, -0.2, -0.3, -0.4, -0.5, -0.6, -0.7,\ldots$ and  $h^*=0,3,7,\ldots$, then $x\downarrow h = 0.0,-0.3,-0.7,\ldots$ 

### Upsampling

The reverse _upsampling_ operation, notated $\uparrow h$, expands the input signal by repeating the missing values. 
$$
x\uparrow h = \lambda t.x(h^+(t)-1)
$$

For example if $ x = 0.0,-0.3,-0.7,\ldots$  and $h^+=1,1,1,2,2,2,2,3,3,\ldots$ then $x \uparrow h = 0.0,0.0,0.0,-0.3,-0.3,-0.3,-0.3,-0.7,\ldots$ 

> _NOTE_: please note that $\uparrow h:\downarrow h$ is the identity function, but that is not true for $\downarrow h:\uparrow h$.

### Semantics of $\mathtt{ondemand}(P)$

We now have all the elements to define the semantics of $\mathtt{ondemand}(P)$. Let's $P$ be a signal processor with $n$ inputs and $m$ outputs.  The semantics of $\mathtt{ondemand}(P)$ is defined by the following rule:
$$
\frac{[\![P]\!](x_1\downarrow h,\ldots,x_n\downarrow h)=(y_1,\ldots,y_m)}
{[\![\mathtt{ondemand}(P)]\!](h, x_1,\ldots,x_n)= (y_1 \uparrow h,\ldots,y_m\uparrow h)}
$$

As we can see, $[\![\mathtt{ondemand}(P)]\!]$ is basically $[\![P]\!]$ applied to downsampled versions of the input signals: $x_i\downarrow h$. The downsampling depends on the demand clock $h$. Intuitively this corresponds to the fact that the values of the input signals are lost between two computation demands. Symmetrically the $y_i$ signals returned by P have to be upsampled: $y_i\uparrow h$. This is illustrated by the following block-diagram

<img src="./images/ondemand1.png" alt="ondemand1" style="zoom:50%;" />

## Combining on-demands

What happens when we combine on-demands ? Can we factorize on-demands ? For example, is the sequencial composition of two on-demands with the same clock equivalent to the on-demand of the sequential composition of the inner processors ? We need to be able to answer these questions in order to normalize Faust expressions and generate the most efficient code.

### Notation

Let's start by defining some additional notation. Instead of writing the on-demand version of $P$ controlled by clock $h$ as the partial application: $\mathtt{ondemand}(P)(h)$, we will simply write $P\downarrow h$. 

Let's also notate $1_h=1,1,1,\ldots$ the clock signal that contains only 1s, that is a demand every tick, and $0_h=0,0,0,\ldots$ the clock signal that contains only 0s and therefore no computation demands at all. 

### Combining Clocks

We are interested in understanding what happens when we write something like: $(P\downarrow h_0)\downarrow h_1)$. There is, of course, an equivalent clock $h_3$ such that $(P\downarrow h_0)\downarrow h_1) = P\downarrow h_3$. But how do we compute it? 

Let's call $\otimes$ the operation that combines two clock signals and such that:
$$
(P\downarrow h_0)\downarrow h_1) = P\downarrow(h_0\otimes h_1)
$$
Let's see what the propertiecs of $\otimes$ are.

### Identities

There are two remarkable identities, related to the $1_h$ and $0_h$ clocks, that need to be taken into account:
$$
\begin{align}
(P\downarrow 1_h)\downarrow h) &= P\downarrow h = (P\downarrow h)\downarrow 1_h)\\
(P\downarrow 0_h)\downarrow h) &= P\downarrow 0_h = (P\downarrow h)\downarrow 0_h)
\end{align}
$$
We therefore deduce that:
$$
\begin{align}
1_h\otimes h &= h\otimes 1_h = h\\
0_h\otimes h &= h\otimes 0_h = 0_h
\end{align}
$$
  ### A Manual Example

Let's first manually compute the demands for  $(P\downarrow h_0)\downarrow h_1)$ with 
$$
\begin{split}
h_0             &=1,0,1,0,1,0,1,0,1,0,\ldots\\
h_1             &=1,1,0,1,0,0,1,0,0,0,\ldots\\
tick	&=0,1,2,3,4,5,6,7,8,9,\ldots
\end{split}
$$
- at tick $0$ we have a demand because $h_1(0)=1$ and $h_0(0)=1$ ; 
- at tick 1 we have no demand because $h_1(1)=1$, but $h_0(1)=0$; 
- at tick 2 we have no demand because $h_1(2)=0$, moreover no demand is propagated to $h_0$; 
- at tick 3 we have a demand because $h_1(3)=1$ and $h_0(2)=1$;
- Etc.

$$
\begin{split}
h_0             &=1,0,1,0,1,0,1,0,1,0,\ldots\\
h_1             &=1,1,0,1,0,0,1,0,0,0,\ldots\\
tick	&=0,1,2,3,4,5,6,7,8,9,\ldots\\
h_0\otimes h_1         &=1,0,0,1,0,0,0,0,0,0,\ldots\\
\end{split}
$$

We can better understand how $h_0\otimes h_1$ is computed by aligning $h_0$ values on top of $h_1$ demands:


$$
\begin{split}
h_0             &=1,0,  &1,    &0,      &\ldots\\
h_1             &=1,1,0,&1,0,0,&1,0,0,0,&\ldots\\
h_0\otimes h_1  &=1,0,0,&1,0,0,&0,0,0,0,&\ldots\\
\end{split}
$$



### General Rule

The property to observe from this manual example that one does not necessarily progress to all ticks in $h_0$. In reality, we only progress in $h_0$ when there are requests in $h_1$. In other words, when we are at the tick $t$ in $h_1$ we are only at the tick $h_1^+(t)-1$ in $h_0$. Furthermore, for a request to reach $P$ it is necessary to have $h_1(t)$ and $h_0(h_1^+(t)-1)$ at $1$. We can now write down the general rule:
$$
(h_0\otimes h_1)(t)=h_1(t)*h_0(h_1^+(t)-1)
$$
It turns out that we've already met part of this formula with our upsampling function. So we can rewrite our definition as follows:
$$
(h_0\otimes h_1)=h_1*(h_0\uparrow h_1)
​					
$$

If we had chosen a more traditional upsampling function (without repetition, but with insertion of 0) we would have had simply: $\otimes=\uparrow$.

### Commutativity

Is $\otimes$ commutative ? Let's try with an example:
$$
\begin{split}
h_0   									&=1,0,1,0,1,0,1,0,1,0,\ldots\\
h_1   									&=1,1,0,1,0,0,1,0,0,0,\ldots\\
h_0\otimes h_1					&=1,0,0,1,0,0,0,0,0,0,\ldots\\
h_1\otimes h_0         	&=1,0,1,0,0,0,1,0,0,0\ldots\\
\end{split}
$$
As we see $h_1\otimes h_0 \neq h_0 \otimes h_1$, therefore $\otimes$ is not a commutative operation and as a result:
$$
(P\downarrow h_0)\downarrow h_1 \neq (P\downarrow h_1)\downarrow h_0
$$

### Associativity

Another interesting property is to check is associativity. This is an important one for the Faust compiler because it allows it to reorganize and factorize the generated code more easily. So, do we have: $((h_0\otimes h_1)\otimes h_2)=(h_0\otimes (h_1\otimes h_2))$ ?

###### Notation

To lighten the notation during the proof we will use capital letters $A,B,C$ for clocks and write $A'=aA$ to indicate that $A'(0)=a$ and $A'(t\ge 1)=A(t-1)$.

Using our new notation we can reformulate the clock composition operation $\otimes$ with two rewriting rules:
$$
\begin{split}
A\otimes 0B &\stackrel{\alpha}{\longrightarrow} 0(A\otimes B)\\
aA\otimes 1B &\stackrel{\beta}{\longrightarrow} a(A\otimes B)
\end{split}
$$

###### Associativity as a predicate

We want to check that $\otimes$ is associative for every possible clocks. We can reformulate that as a predicate $\mathcal{P}$ on triplets of clocks:
$$
\mathcal{P}(A,B,C) \stackrel{\text{def}}{=} (A\otimes B)\otimes C=A\otimes(B\otimes C)
$$
and check that P is true for all possible triplets of clocks.

###### Inductive set 

To do that, we need an inductive definition of the set of triplets of clocks. For the simplicity reasons we are not considering arbitrary clocks but only clocks that end with an infinite sequence of 0s. 

Let's call $\mathbb{H}$ this specific set of clocks. Here is its inductive definition:

- $0_h \in \mathbb{H}$
- $A\in \mathbb{H} \implies 0A\in \mathbb{H}$
- $A\in \mathbb{H} \implies 1A\in \mathbb{H}$
- Nothing else is in $\mathbb{H}$.

The set of triplets of clocks we are interested in is $\mathbb{H}\times \mathbb{H}\times \mathbb{H}$. But we need an inductive definition of it. Here is one:
- Base case: $\forall A,B \in \mathbb{H},(A,B,0_h) \in \mathbb{H}^3$
- Induction step 1: $(A,B,C)\in \mathbb{H}^3 \implies (A,B,0C)\in \mathbb{H}^3$
- Induction step 2: $(A,B,C)\in \mathbb{H}^3 \implies (A,0B,1C)\in \mathbb{H}^3$
- Induction step 3: $(A,B,C)\in \mathbb{H}^3 \implies (0A,1B,1C)\in \mathbb{H}^3$
- Induction step 4: $(A,B,C)\in \mathbb{H}^3 \implies (1A,1B,1C)\in \mathbb{H}^3$
- Nothing else is in $\mathbb{H}^3$.

To be sure that our inductive definition is correct, we need first to prove that the resulting set $\mathbb{H}^3$ is equivalent to $\mathbb{H}\times\mathbb{H}\times\mathbb{H}$ in other words that :

- a) $\forall(A,B,C)\in\mathbb{H}^3\implies A,B,C\in\mathbb{H}$
- b) $\forall A,B,C\in\mathbb{H}\implies(A,B,C)\in\mathbb{H}^3$

_Proof_: 

- a) trivial 

- b) We provide a recursive proof that is guaranteed to end on a base case $(A,B,0_h)\in\mathbb{H}^3$ because one element of C is removed at each iteration leading to $0_h$ after a finite number of iterations.

  - to prove $(0A,0B,0C)\in\mathbb{H}^3$, prove $(0A,0B,C)\in\mathbb{H}^3$ and use induction step 1

  - to prove $(0A,0B,1C)\in\mathbb{H}^3$, prove $(0A,B,C)\in\mathbb{H}^3$ and use induction step 2

  - to prove $(0A,1B,0C)\in\mathbb{H}^3$, prove $(0A,1B,C)\in\mathbb{H}^3$ and use induction step 1

  - to prove $(0A,1B,1C)\in\mathbb{H}^3$, prove $(A,B,C)\in\mathbb{H}^3$ and use induction step 3

  - to prove $(1A,0B,0C)\in\mathbb{H}^3$, prove $(0A,0B,C)\in\mathbb{H}^3$ and use induction step 1

  - to prove $(1A,0B,1C)\in\mathbb{H}^3$, prove $(1A,B,C)\in\mathbb{H}^3$ and use induction step 2

  - to prove $(1A,1B,0C)\in\mathbb{H}^3$, prove $(1A,1B,C)\in\mathbb{H}^3$ and use induction step 1

  - to prove $(1A,1B,1C)\in\mathbb{H}^3$, prove $(A,B,C)\in\mathbb{H}^3$ and use induction step 4

    

#### Proof of Associativity

To prove $\mathcal{P}$ for all elements of $\mathbb{H}^3$, we have to prove it for the base cases and for the four induction steps.

###### Base case: $\mathcal{P}(A,B,0_h)$ is true.

_Proof_:
$$
(A \otimes B)\otimes 0_h
	\rightarrow 
	0_h
	\leftarrow
	A\otimes 0_h
	\leftarrow
	A \otimes (B\otimes 0_h)
$$

###### Induction step 1: $P(A,B,C) \implies P(A,B,0C)$
_Proof_: 
$$
	(A\otimes B)\otimes 0C 
	\rightarrow 
	0((A\otimes B)\otimes C) = 0(A\otimes (B\otimes C))
	\leftarrow 
	A\otimes 0(B\otimes C)
	\leftarrow 
	A\otimes (B\otimes 0C)
$$

###### Induction step 2: $P(A,B,C) \implies P(A,0B,1C)$
_Proof_: 
$$
	(A\otimes 0B)\otimes 1C 
	\rightarrow 
	0(A\otimes B)\otimes 1C 
	\rightarrow 
	0((A\otimes B)\otimes C)=0(A\otimes (B\otimes C))
	\leftarrow 
	A\otimes 0(B\otimes C)
	\letfarrow 
	A\otimes (0B\otimes 1C)
$$

###### Induction step 3: $P(A,B,C) \implies P(0A,1B,1C)$
_Proof_: 
$$
	(0A\otimes 1B)\otimes 1C 
	\rightarrow 
	0(A\otimes B)\otimes 1C 
	\rightarrow 
	0((A\otimes B)\otimes C) = 0(A\otimes (B\otimes C))
  \leftarrow 
  0A\otimes 1(B\otimes C) 
  \leftarrow 
  0A\otimes (1B\otimes 1C)
$$

###### Induction step 4: $P(A,B,C) \implies P(1A,1B,1C)$
_Proof_: 
$$
	(1A\otimes 1B)\otimes 1C 
	\rightarrow 
	1(A\otimes B)\otimes 1C 
	\rightarrow 
	1(A\otimes B)\otimes C = 1(A\otimes(B\otimes C)) 
	\leftarrow 
	1A\otimes1(B\otimes C)
	\leftarrow 
	1A\otimes(1B\otimes 1C)
$$

$\square$




