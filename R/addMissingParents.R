#' Add missing parents to a pedigree adjacency matrix
#'
#' @param a An adjMatrix object
#' @param maxLinearInb A nonnegative integer, or `Inf` (default). If this is a
#'   finite number, it disallows mating between pedigree members X and Y if X is
#'   a linear descendant of Y separated by more than the given number. For
#'   example, setting `maxLinearInb = 0` forbids mating between parent-child,
#'   grandparent-grandchild, a.s.o. If `maxLinearInb = 1` then parent-child
#'   matings are allowed, but not grandparent-grandchild or higher.
#' @param sexSymmetry A logical. If TRUE, pedigrees which are equal except for
#'   the gender distribution of the *added* parents, are regarded as equivalent,
#'   and only one of each equivalence class is returned. Example: paternal vs
#'   maternal half sibs.
#' @return A list of adjMatrix objects where all columns sum to either 0 or 2.
#'
#' @examples
#' a = adjMatrix(c(0,0,1,0), sex=c(1,1))
#' pedbuildr:::addMissingParents(a)
#'
#' b = adjMatrix(rbind(c(0,1,1,1), 0,0,0), sex=c(1,1,1,1))
#' pedbuildr:::addMissingParents(b)
#'
#' @noRd
addMissingParents = function(a, maxLinearInb = Inf, sexSymmetry = FALSE) {
  sex = attr(a, "sex")
  n = ncol(a)
  idvec = seq_len(n)

  missingFa = idvec[colSums(a[sex == 1, , drop = FALSE]) == 0]
  missingMo = idvec[colSums(a[sex == 2, , drop = FALSE]) == 0]

  nMissFa = length(missingFa)
  nMissMo = length(missingMo)

  if(nMissFa > 7) stop2("More than 7 extra fathers needed: Too many possible combinations")
  if(nMissMo > 7) stop2("More than 7 extra mothers needed: Too many possible combinations")

  # Founders (needed in a later step)
  fou = idvec[colSums(a) == 0]

  # Setup for gender symmetry restriction
  if(sexSymmetry) {
    observedInvariants = character()
    pows = 2^(0:(n - 1))
  }

  # List of descendants
  checkInb = maxLinearInb < Inf
  if(checkInb)
    descList = lapply(1:n, function(id)
      dagDescendants(a, id, minDist = maxLinearInb + 1))

  # All set partitions for the fathers and the mothers
  if(nMissFa > 0)
    pFa = partitions[[nMissFa]]
  else
    pFa = list(matrix(0L, ncol=1, nrow=1))

  if(nMissMo > 0)
    pMo = partitions[[nMissMo]]
  else
    pMo = list(matrix(0L, ncol=1, nrow=1))

  # Loop over all combinations
  res = vector(length(pFa) * length(pMo), mode = "list")
  for(i in seq_along(pFa)) for(j in seq_along(pMo)) {
    pf = pFa[[i]]
    pm = pMo[[j]]
    newfa = max(pf)
    newmo = max(pm)
    newpars = newfa + newmo

    # Matrix blocks to be added at the bottom of a
    FA = matrix(0L, ncol = n, nrow = newfa)
    FA[cbind(pf, missingFa)] = 1L

    MO = matrix(0L, ncol = n, nrow = newmo)
    MO[cbind(pm, missingMo)] = 1L

    bottom = rbind(FA, MO)

    # Gender restriction
    if(sexSymmetry && newpars > 1) {
      inv_vec = .rowSums(bottom * rep(pows, each = newpars), m = newpars, n = n)
      inv = paste(.mysortInt(inv_vec), collapse = "-")
      if(inv %in% observedInvariants)
        next
      observedInvariants = c(observedInvariants, inv)
    }

    # Add blocks and create adjMatrix object
    adjExp = rbind(a, bottom)
    adjExp = cbind(adjExp, matrix(0L, ncol = newpars, nrow = nrow(adjExp)))

    # Check linear inbreeding
    if(checkInb && linearInb(adjExp, descList = descList))
      next

    # Create adjMatrix object
    sexExp = c(sex, rep(1L, newfa), rep(2L, newmo))
    A = adjMatrix(adjExp, sexExp, validate = FALSE)

    # Remove superfluous added parents
    A = removeFounderParents(A, fou)

    res[[length(pMo) * (i-1) + j]] = A
  }

  res[!unlist(lapply(res, is.null))]
}



# Remove parents of original founders, unless these parents have other children
removeFounderParents = function(adj, fou) {
  if(length(fou) == 0)
    return(adj)

  idvec = seq_len(dim(adj)[1])

  remov = integer()
  for(id in fou) {
    pars = adj[, id]
    if(!any(adj[pars, -id])) # If parents have no other children
      remov = c(remov, idvec[pars])
  }

  if(length(remov) > 0) {
    sex = attr(adj, 'sex')
    adj = newAdjMatrix(adj[-remov, -remov], sex[-remov])
  }

  adj
}


# Input: adj matrix with the original indivs
# Ouput: adj matrix extended with missing parents - only when 1 is missing
# All the added parents are unrelated to all other indivs
addMissingParents1 = function(a) {
  n = dim(a)[1]
  sex = attr(a, "sex")

  isMale = sex == 1
  nMale = sum(isMale)

  # identify those missing (exactly) 1 parent
  missfa = .colSums(a[isMale, , drop = FALSE], nMale, n) == 0
  missmo = .colSums(a[!isMale, , drop = FALSE], n - nMale, n) == 0

  miss1 = which(xor(missfa, missmo))
  Nmiss = length(miss1)
  if(Nmiss == 0)
    return(a)

  Ntot = n + Nmiss

  # Add matrix block at the bottom
  bottom = rep(FALSE, n * Nmiss)
  dim(bottom) = c(Nmiss, n)
  bottom[cbind(seq_along(miss1), miss1)] = TRUE
  adjExp = rbind(a, bottom)

  # Add block to the right
  adjExp = c(adjExp, rep(FALSE, Ntot * Nmiss))
  dim(adjExp) = c(Ntot, Ntot)

  # Expand sex vector
  addedSex = rep(1L, Nmiss)
  addedSex[missmo[miss1]] = 2L
  sexExp = c(sex, addedSex)

  # Return as adjMatrix object
  newAdjMatrix(adjExp, sexExp, connected = attr(a, "connected"))
}


