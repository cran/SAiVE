% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/thinFeatures.R
\name{thinFeatures}
\alias{thinFeatures}
\title{Remove irrelevant predictor variables}
\usage{
thinFeatures(data, outcome_col, n.cores = NULL)
}
\arguments{
\item{data}{A data.frame containing a column for the outcome variable and \emph{n} columns for predictor variables.}

\item{outcome_col}{The name of the outcome variable column.}

\item{n.cores}{The maximum number of cores to use. Leave NULL to use all cores minus 1.}
}
\value{
A list of two data.frames: the outcome of the VSURF algorithm and the data after applying the VSURF results (rows removed if applicable)
}
\description{
Uses \code{\link[VSURF:VSURF]{VSURF::VSURF()}} to build random forests and remove irrelevant predictor variables from a data.frame containing an outcome variable and 2 or more predictor variables.
}
\examples{
\dontshow{if (interactive()) (if (getRversion() >= "3.4") withAutoprint else force)(\{ # examplesIf}

# thinFeatures on 'permafrost' data set

data(permafrost)
res <- thinFeatures(permafrost, "Type", n.cores = 2)

# Results will vary due to inherent randomness of random forests!
\dontshow{\}) # examplesIf}
}
