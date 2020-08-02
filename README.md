---
author: 'Yann Orlarey'
title: 'On-demand computations in Faust'
---



# _On-demand_ computations in Faust

## Introduction

There are requests for using Faust in a more _composition-oriented_ way. This can be done by introducing _on-demand_ computations. The challenge is to do that while keeping the simple and well-defined semantics of Faust.

For that purpose, we introduce a new $\mathtt{ondemand}(P)\rightarrow P'$ primitive that operates on signal processors (not on signals). Informally, the resulting signal processor $P'$ is like $P$, but with an additional input for a clock signal and an _on-demand_ semantics. As we will see, this _on-demand_ semantics can be expressed using the regular Faust semantics but applied to downsampled signals.

## Type of $\mathtt{ondemand}(P)$

If $P$ has $n$ inputs and $m$ outputs, then $\mathtt{ondemand}(P)$ has $n+1$ inputs and $m$ outputs. The additional input is a clock signal.
$$
\frac{P:n\rightarrow m}{\mathtt{ondemand}(P):1+n\rightarrow m}
$$


## The clock signals $h$

The additional input of $\mathtt{ondemand}(P)$ is a clock signal $h$ that indicates by a $1$ when there is a computation demand, and by $0$ otherwise. In other words, $h(t)=1$ means that there is a computation demand at time $t$.

Form signal $h$ we can derive a signal $\bar{h}$ that indicates the time of each demand. For example if $h=1,0,0,1,0,0,0,1,0\ldots$ then $\bar{h}=0,3,7,\ldots$ indicating that the first demand is at time $0$, the second one at time $3$, the third one at time $7$, etc.

We derive also another signal $h^+$ that _counts_ the number of demands: $h^+(t) = h^+(t-1)+h(t)$ (with $h^+(t<0)=0$). For the same $h=1,0,0,1,0,0,0,1,0\ldots$ we have $h^+=1,1,1,2,2,2,2,3,3,\ldots$

## Downsampling and Upsampling

Now that we have defined the clocks signals $h$ and $\bar{h}$, we can introduce the _downsampling_ and _upsampling_  operations needed to express the _on-demand_ semantics. 

### Downsampling

The downsamplig operation is notated $\downarrow_{h}$. For a signal $x$, the downsampled signal $\downarrow_{h}(x)$ is defined as:
$$
\downarrow_{h}(x) = \lambda t.x(\bar{h}(t))
$$
For example if $x=0.0, -0.1, -0.2, -0.3, -0.4, -0.5, -0.6, -0.7,\ldots$ and  $\bar{h}=0,3,7,\ldots$, then $\downarrow_{h}(x) = 0.0,-0.3,-0.7,\ldots$ 

### Upsampling

The reverse _upsampling_ operation, notated $\uparrow_{h}$, expands the input signal by repeating the missing values. 
$$
\uparrow_{h}(x) = \lambda t.x(h^+(t)-1)
$$

For example if $ x = 0.0,-0.3,-0.7,\ldots$  and $h^+=1,1,1,2,2,2,2,3,3,\ldots$ then $\uparrow_{h}(x) = 0.0,0.0,0.0,-0.3,-0.3,-0.3,-0.3,-0.7,\ldots$ 

> _NOTE_: please note that $\uparrow_{h}:\downarrow_{h}$ is the identity function, but that is not true for $\downarrow_{h}:\uparrow_{h}$.

# Semantics of $\mathtt{ondemand}(P)$

## Semantics of Faust expressions

The semantics (i.e. meaning) of Faust expressions is defined in terms of _signal processors_, mathematical functions on signals. In order to distinguish a Faust expression from its meaning, we use semantics brackets $[\![\ ]\!]$. For example $[\![+]\!]$ represents the meaning of the Faust expression $+$ and has the following definition:
$$
[\![+]\!](x,y) = \lambda t.(x(t)+y(t))
$$
where $x$, $y$ and $\lambda t.(x(t)+y(t))$ represent signals.

### Signals

A _signal_ $s\in\mathbb{S}\subset\mathbb{Z}\rightarrow\mathbb{R}$ is a discrete-time function. The sample value of a signal $s$ at a specific time-point $t\in\mathbb{Z}$ is notated $s(t)$. The actual computation time starts at $t=0$, but to take into account _delay_ operations, signals are extended toward $-\infty$ with 0 values. In other words $\forall s\in\mathbb{S}, s(t<0)=0$.

### Signal Processors

A Faust expression $P$, with $n$ inputs and $m$ outputs, denotes a _signal processor_ $[\![P]\!]:\mathbb{S}^n\rightarrow\mathbb{S}^m$, a function that takes a $n$-tuple of signals as an input and returns a $m$-tuple of signals as a result.

## Semantics of $\mathtt{ondemand}(P)$

We now have all the elements to define the semantics of $\mathtt{ondemand}(P)$. Let's $P$ be a signal processor with $n$ inputs and $m$ outputs.  The semantics of $\mathtt{ondemand}(P)$ is defined by the following rule:
$$
\frac{[\![P]\!](\downarrow_h(x_1),\ldots,\downarrow_h(x_n))=(y_1,\ldots,y_m)}
{[\![\mathtt{ondemand}(P)]\!](h, x_1,\ldots,x_n)= (\uparrow_h(y_1),\ldots,\uparrow_h(y_m))}
$$

As we can see, $[\![\mathtt{ondemand}(P)]\!]$ is basically $[\![P]\!]$ applied to downsampled versions of the input signals: $\downarrow_h(x_i)$. The downsampling depends on the demand clock $h$. Intuitively this corresponds to the fact that the values of the input signals are lost between two computation demands. Symmetrically the $y_i$ signals returned by P have to be upsampled.

