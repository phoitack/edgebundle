#' @title Sample points for triangulated networks
#' @description uses various sampling strategies to create dummy nodes for the [tnss_tree]
#' @param xy coordinates of "real" nodes
#' @param root root node id
#' @param circ logical. create circular dummy nodes around leafs.
#' @param line logical. create dummy nodes on a straight line between root and leafs.
#' @param diag logical. create dummy nodes diagonally through space.
#' @param grid logical. create dummy nodes on a grid.
#' @param rand logical. create random dummy nodes.
#' @param ncirc numeric. number of circular dummy nodes per leaf.
#' @param rcirc numeric. radius of circles around leaf nodes.
#' @param nline numeric. number of straight line nodes per leaf.
#' @param ndiag numeric. number of dummy nodes on diagonals.
#' @param ngrid numeric. number of dummy nodes per dim on grid.
#' @param nrand numeric. number of random nodes to create.
#' @return coordinates of dummy nodes
#' @author David Schoch
#' @export

tnss_dummies <- function(xy,root,
                          circ = TRUE,
                          line = TRUE,
                          diag = TRUE,
                          grid = FALSE,
                          rand = FALSE,
                          ncirc = 9,
                          rcirc = 2,
                          nline = 10,
                          ndiag = 50,
                          ngrid = 50,
                          nrand = 50){

  n <- nrow(xy)
  verts <- 1:n
  leafs <- setdiff(verts,root)
  dat <- matrix(0,0,2)

  # circular points around leafs
  if(circ){
    angles <- seq(0.01,0.99*2*pi,length.out = ncirc)
    r <- rcirc
    xy_circle <- do.call(rbind,lapply(leafs,function(x) cbind(xy[x,1] + r*cos(angles),xy[x,2] + r*sin(angles)) ))
    dat <- rbind(dat,xy_circle)
  }

  #points on line from source to leafs
  if(line){
    tseq <- seq(0.2,0.9,length.out = nline)
    xy_lines <- do.call(rbind,lapply(leafs,function(x) cbind(xy[x,1] * tseq + xy[root,1] * (1-tseq), xy[x,2] * tseq + xy[root,2] * (1-tseq)) ))
    dat <- rbind(dat,xy_lines)
  }

  #diagonals through space
  if(diag){
    pts_tr <- c(max(xy[,1]),max(xy[,2]))
    pts_br <- c(max(xy[,1]),min(xy[,2]))
    pts_bl <- c(min(xy[,1]),min(xy[,2]))
    pts_tl <- c(max(xy[,1]),max(xy[,2]))
    pts_extra <- rbind(pts_tr,pts_br,pts_bl,pts_tl)
    tseq <- seq(0.1,0.9,length.out = ndiag)
    xy_extra <- do.call(rbind,lapply(1:4,function(x) cbind(pts_extra[x,1] * tseq + xy[root,1] * (1-tseq), pts_extra[x,2] * tseq + xy[root,2] * (1-tseq)) ))
    dat <- rbind(dat,xy_extra)
  }

  # create an equidistant grid
  if(grid){
    xdiff <- seq(min(xy[,1]),max(xy[,1]),length.out = ngrid)
    ydiff <- seq(min(xy[,2]),max(xy[,2]),length.out = ngrid)
    xy_grid <- as.matrix(expand.grid(xdiff,ydiff))
    colnames(xy_grid) <- NULL
    dat <- rbind(dat,xy_grid)
  }

  # some random points
  if(rand){
    xy_rand <- cbind(stats::runif(nrand,min(xy[,1]),max(xy[,1])),stats::runif(50,min(xy[,2]),max(xy[,2])))
    dat <- rbind(dat,xy_rand)

  }

  dat[!duplicated(dat),]
}

#' @title Create steiner tree from real and dummy points
#' @description creates an approximated steiner tree for a flow map visualization
#' @param g original flow network (must be a one-to-many flow network, i.e star graph). Must have a weight attribute indicating the flow
#' @param xy coordinates of "real" nodes
#' @param xydummy coordinates of "dummy" nodes
#' @param root root node id of the flow
#' @param gamma edge length decay parameter
#' @param epsilon smoothing factor for Douglas-Peucker Algorithm
#' @return approximated steiner tree from dummy and real nodes as igraph object
#' @references Sun, Shipeng. "An automated spatial flow layout algorithm using triangulation, approximate Steiner tree, and path smoothing." AutoCarto, 2016.
#' @author David Schoch
#' @examples
#' xy <- cbind(state.center$x,state.center$y)[!state.name%in%c("Alaska","Hawaii"),]
#' xy_dummy <- tnss_dummies(xy,root = 4)
#' gtree <- tnss_tree(cali2010,xy,xy_dummy,root = 4,gamma = 0.9)
#' @export

tnss_tree <- function(g,xy,xydummy,root,gamma = 0.9,epsilon = 0.3){

  xymesh <- rbind(xy,xydummy)

  n <- nrow(xy)
  verts <- 1:n
  leafs <- setdiff(verts,root)

  #triangulate points
  tria <- interp::tri.mesh(xymesh[,1],xymesh[,2])

  # create network
  g1 <- igraph::graph_from_edgelist(rbind(tria$trlist[,1:2],tria$trlist[,2:3]),F)
  g1 <- igraph::simplify(g1)
  igraph::V(g1)$tnss <- "dummy"
  igraph::V(g1)$tnss[1:nrow(xy)] <- "real"
  igraph::V(g1)$x <- xymesh[,1]
  igraph::V(g1)$y <- xymesh[,2]

  # g1$name <- "triangulated network"

  # edge weights from distances
  el <- igraph::get.edgelist(g1,FALSE)
  edges_xy <- cbind(xymesh[el[,1],1],xymesh[el[,1],2],xymesh[el[,2],1],xymesh[el[,2],2])
  igraph::E(g1)$weight <- apply(edges_xy,1,function(x) sqrt((x[1]-x[3])^2+(x[2]-x[4])^2))

  # calculate all shortest paths to eliminate dummy nodes
  sp_nodes <- vector("list",length(leafs))
  sp_edges <- vector("list",length(leafs))
  k <- 0

  g2 <- igraph::as.directed(g1,"mutual")
  ide <- which(igraph::get.edgelist(g2,FALSE)[,1]%in%leafs)
  g2 <- igraph::delete.edges(g2,ide)


  dist2root <- sqrt((xy[root,1]-xy[leafs,1])^2 + (xy[root,2]-xy[leafs,2])^2)
  # minew <- min(igraph::E(g2)$weight)
  # leafs_order <- leafs[order(dist2root,decreasing = TRUE)]
  for(dest in leafs){
    k <- k + 1
    sp_list <- igraph::shortest_paths(g2, from = root,to = dest,weights = igraph::E(g2)$weight,output = "both")
    sp_nodes[[k]] <- unlist(sp_list$vpath[[1]])
    sp_edges[[k]] <- unlist(sp_list$epath[[1]])

    igraph::E(g2)$weight[sp_edges[[k]]] <- gamma*igraph::E(g2)$weight[sp_edges[[k]]]#+0.01*minew

  }
  del_nodes <- unique(unlist(sp_nodes))
  del_edges <- unique(unlist(sp_edges))

  g3 <- igraph::delete.edges(g2,which(!((1:igraph::ecount(g2))%in%del_edges)))
  idx <- which(!igraph::V(g3)%in%del_nodes)
  g3 <- igraph::delete.vertices(g3,idx)

  #straighten edges
  xymesh1 <- xymesh[-idx,]
  g4 <- igraph::as.undirected(g3)
  g4 <- igraph::delete_edge_attr(g4,"weight")
  deg <- igraph::degree(g4)
  del2 <- c()
  for(dest in leafs){
    sp <- unlist(igraph::shortest_paths(g4,from = root,to=dest)$vpath)
    keep <- which(duplicated(rbind(xymesh1[sp,],DouglasPeucker(xymesh1[sp,],epsilon = epsilon)),fromLast = TRUE))
    del <- sp[-keep]
    del <- del[deg[del]==2]
    del2 <- c(del2,del)
  }

  if(is.null(igraph::V(g4)$name)){
    igraph::V(g4)$name <- paste0("dummy_",1:igraph::vcount(g4))
  }
  if(!is.null(igraph::V(g)$name)){
    igraph::V(g4)$name[1:n] <- igraph::V(g)$name
  }
  del2_name <- igraph::V(g4)$name[unique(del2)]
  g5 <- g4
  for(v in del2_name){
    ni <- igraph::neighborhood(g5,1,v,mindist = 1)
    g5 <- igraph::add.edges(g5,unlist(igraph::neighborhood(g5,1,v,mindist = 1)))
    g5 <- igraph::delete_vertices(g5,v)
  }

  #calculate flow from edge weight
  gfinal <- g5
  igraph::E(gfinal)$flow <- 0
  el <- igraph::get.edgelist(g,FALSE)
  for(dest in leafs){
    ide <- which(el[,1]==dest | el[,2]==dest)
    w <- igraph::E(g)$weight[ide]
    sp <- igraph::shortest_paths(gfinal,root,dest,weights = NA,output = "epath")

    igraph::E(gfinal)$flow[unlist(sp$epath)] <- igraph::E(gfinal)$flow[unlist(sp$epath)] + w
  }
  gfinal$name <- "approx steiner tree"
  igraph::V(gfinal)$tnss[root] <- "root"
  igraph::V(gfinal)$tnss[leafs] <- "leaf"
  gfinal
}


# helpers ----
DouglasPeucker <- function(points,epsilon){
  dmax <- 0
  index <- 0
  end <- nrow(points)
  ResultList <- numeric(0)
  if (end<3) return (ResultList <- rbind(ResultList,points))
  for (i in 2:(end-1)){
    d <- ShortestDistance(points[i,], line=rbind(points[1,],points[end,]))
    if (d>dmax){
      index <- i
      dmax <- d
    }
  }
  #if dmax is greater than epsilon recursively apply
  if (dmax>epsilon){
    recResults1 <- DouglasPeucker(points[1:index,],epsilon)
    recResults2 <- DouglasPeucker(points[index:end,],epsilon)
    ResultList <- rbind(ResultList,recResults1,recResults2)

  }
  else
  {
    ResultList <- rbind(ResultList,points[1,],points[end,])
  }
  ResultList <- as.matrix(ResultList[!duplicated(ResultList),])
  colnames(ResultList)=c("x","p")
  return(ResultList)
}

ShortestDistance <- function(p, line){
  x1 <- line[1,1]
  y1 <- line[1,2]
  x2 <- line[2,1]
  y2 <- line[2,2]
  x0 <- p[1]
  y0 <- p[2]
  d=abs((y2-y1)*x0-(x2-x1)*y0+x2*y1-y2*x1)/sqrt((y2-y1)^2+(x2-x1)^2)
  return(as.numeric(d))
}
