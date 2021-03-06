#' Get Available Collections of MODIS Product(s)
#' 
#' @description 
#' Checks and retrieves available MODIS collection(s) for a given product.
#' 
#' @param product \code{character}. MODIS grid product to check for existing 
#' collections, see \code{\link{getProduct}}.
#' @param collection \code{character} or \code{integer}. If provided, the 
#' function only checks if the specified collection exists and returns the 
#' collection number formatted based on the \code{as} parameter or \code{FALSE} 
#' if it doesn't exists. The check is performed on 
#' \href{https://lpdaac.usgs.gov/}{LP DAAC} as the exclusive source for several 
#' (but by far not all) products.
#' @param newest \code{logical}. If \code{TRUE} (default), return only the 
#' newest collection, else return all available collections.
#' @param forceCheck \code{logical}, defaults to \code{FALSE}. If \code{TRUE}, 
#' connect to the 'LP DAAC' FTP server and get available collections, of which 
#' an updated version is permanently stored in 
#' \code{MODIS:::combineOptions()$auxPath}.
#' @param as \code{character}, defaults to \code{'character'} which returns the 
#' typical 3-digit collection number (i.e., \code{"005"}). \code{as = 'numeric'} 
#' returns the result as \code{numeric} (i.e., \code{5}).
#' @param quiet \code{logical}, defaults to \code{TRUE}.
#' @param ... Additional arguments passed to \code{MODIS:::combineOptions}.
#' 
#' @return 
#' A 3-digit \code{character} or \code{numeric} object (depending on 'as') or, 
#' if \code{length(product) > 1}, a \code{list} of such objects with each slot 
#' corresponding to the collection available for a certain product. 
#' Additionally, a text file in a hidden folder located in 
#' \code{getOption("MODIS_localArcPath")} as database for future calls. If 
#' 'collection' is provided, only the (formatted) collection (or \code{FALSE} if 
#' it could not be found) is returned.
#' 
#' @author 
#' Matteo Mattiuzzi, Florian Detsch
#' 
#' @seealso 
#' \code{\link{getProduct}}.
#' 
#' @examples 
#' \dontrun{
#' 
#' # update or get collections for MOD11C3 and MYD11C3
#' getCollection(product="M.D11C3")
#' getCollection(product="M.D11C3",newest=FALSE)
#' 
#' getCollection(product="M.D11C3",collection=3)
#' getCollection(product="M.D11C3",collection=41)
#' getCollection(product="M.D11C3",collection="041")
#' getCollection(product="M.D11C3",forceCheck=TRUE)
#' }
#' 
#' @export getCollection
#' @name getCollection
getCollection <- function(product,collection=NULL,newest=TRUE,forceCheck=FALSE,as="character",quiet=TRUE, ...)
{
    opts <- combineOptions(...)

    ####
    # checks for product
    if (missing(product))
    {
        stop("Please provide a valid product")
    }
    productN <- getProduct(x = if (is.character(product)) {
      sapply(product, function(i) skipDuplicateProducts(i, quiet = quiet))
    } else product, quiet = TRUE)
    if (is.null(productN)) 
    {
        stop("Unknown product")
    }
    
    ## if 'collections' dataset does not exist in opts$auxPath, copy it from 
    ## 'inst/external', then import data
    dir_aux <- opts$auxPath
    if (!dir.exists(dir_aux)) dir.create(dir_aux)
    
    fls_col <- file.path(dir_aux, "collections.RData")
    
    if (!file.exists(fls_col))
      invisible(
        file.copy(system.file("external", "collections.RData", package = "MODIS"), 
                  fls_col)
      )

    load(fls_col)
    
    if (forceCheck | sum(!productN$PRODUCT %in% colnames(MODIScollection))>0) 
    {
      sturheit <- stubborn(level=opts$stubbornness)
      
      load(system.file("external", "MODIS_FTPinfo.RData", package = "MODIS"))
      
      for (i in seq_along(productN$PRODUCT)) 
      {	
        ## retrieve ftp server address based on product source information
        server <- unlist(productN$SOURCE[[i]])
        
        ftp_id <- sapply(MODIS_FTPinfo, function(i) i$name %in% server)
        ftp_id <- which(ftp_id)[1]
        
        ftp <- file.path(MODIS_FTPinfo[[ftp_id]]$basepath, productN$PF1[i], "/")
        cat("Updating collection from", server[1], "for product:"
            , productN$PRODUCT[i], "\n")
        
        if(exists("dirs")) 
        {
          suppressWarnings(rm(dirs))
        }
        for (g in 1:sturheit)
        {
          try(dirs <- filesUrl(ftp))
          if(exists("dirs"))
          {
            if(all(dirs != FALSE))
            {
              break
            }
          }
        } 
        
        if (!exists("dirs")) 
        {
          cat("FTP is not available, using stored information from previous calls (this should be mostly fine)\n")
        } else 
        {
          
          ## choose relevant folders and remove empty ones
          dirs = grep(paste0(productN$PRODUCT[i], "\\.[[:digit:]]{3}"), dirs
                      , value = TRUE)
          
          ids = sapply(file.path(ftp, dirs, "/"), function(ftpdir) {
            cnt = RCurl::getURL(ftpdir, dirlistonly = TRUE)
            dts = regmatches(cnt, regexpr("[[:digit:]]{4}\\.[[:digit:]]{2}\\.[[:digit:]]{2}", cnt))
            
            return(length(dts) > 0)
          })
          
          dirs = dirs[ids]
          
          ## information about products and collections    			  
          ls_prod_col <- sapply(dirs, function(x) {strsplit(x, "\\.")})
          prod <- sapply(ls_prod_col, "[[", 1)
          coll <- sapply(ls_prod_col, "[[", 2)
          
          mtr  <- cbind(prod,coll)
          mtr  <- tapply(INDEX=mtr[,1],X=mtr[,2],function(x){x})
          
          maxrow <- max(nrow(MODIScollection),sapply(mtr,function(x)length(x)))
          
          basemtr <- matrix(NA,ncol=nrow(mtr), nrow = maxrow)
          colnames(basemtr) <- names(mtr)
          
          for(u in 1:ncol(basemtr)) 
          {
            basemtr[1:length(mtr[[u]]),u] <- mtr[[u]]
          }
          
          tmp = as.integer(basemtr)
          tmp[tmp >= 10 & !is.na(tmp)] = tmp[tmp >= 10 & !is.na(tmp)] / 10
          basemtr = matrix(as.integer(basemtr[order(tmp), ])
                           , ncol = nrow(mtr), nrow = maxrow)
          colnames(basemtr) = names(mtr)
          
          ## if new collections are available, 
          ## add additional rows to 'MODIScollection'
          if (nrow(MODIScollection) < maxrow & nrow(MODIScollection) > 0) 
          {
            new_rows <- matrix(data = NA, nrow = maxrow-nrow(MODIScollection), 
                               ncol = ncol(MODIScollection))
            new_rows <- data.frame(new_rows)
            names(new_rows) <- names(MODIScollection)
            
            MODIScollection <- rbind(MODIScollection, new_rows)
          }
          
          if (ncol(MODIScollection)==0)
          { # relevant only for time
            MODIScollection <- data.frame(basemtr) # create new
          } else 
          { # or update the available one
            MODIScollection[, colnames(basemtr)] = basemtr
          }
        }
      }
    }
    
    #write.table(MODIScollection,file.path(opts$auxPath,"collections",fsep="/"))
    ind <- which(colnames(MODIScollection)%in%productN$PRODUCT)

    if(length(ind)==1)
    {
	    res <- list(MODIScollection[,ind])
	    names(res) <- colnames(MODIScollection)[ind]
    } else if (length(ind)>1) 
    {
	    res <- as.list(MODIScollection[,ind])
    } else 
    {
	    stop("No data available, check product input?") # should not happen getProduct() should catch that before
    }

    res <- lapply(res, function(x){as.numeric(as.character(x[!is.na(x)]))})

    if (!is.null(collection)) 
    { # if collection is provided...return formatted collection or 'FALSE'
	
	    isOk <- lapply(res,function(x)
	    {
		    if (as.numeric(collection) %in% x)
		    {
				as.numeric(collection)
			} else 
			{
				FALSE		
			}
		})
	
	    if (sum(isOk==FALSE)==length(isOk)) 
	    {
		    cat("Product(s) not available in collection '",collection,"'. Try 'getCollection('",productN$request,"',newest=FALSE,forceCheck=TRUE)'\n",sep="")
	        return(invisible(isOk))
	    } else if (sum(isOk==FALSE)>0 & sum(isOk==FALSE)<length(isOk))
	    {
		    cat("Not all the products in your input are available in collection '", collection,"'. Try 'getCollection('", productN$request, "', newest=FALSE, forceCheck=TRUE)'\n", sep="")
	    }

	    res <- isOk[isOk!=FALSE]

    } else if (newest) 
    {
	    if (!quiet) {
	      cat("No collection specified, getting the newest for", productN$PRODUCT, "\n")
	    }

	    res <- lapply(res,function(x)
	    { #select the newest
		    x[order(sapply(x,function(c){		
		    s <- nchar(c)-1
		    if (s==0) 
		    {
		    	c
		    } else 
		    {
		    	c/as.numeric(paste(1,rep(0,s),sep=""))
		    }}),decreasing=TRUE)][1]
		})
    }   

    if (as=="character") 
    {
	    res <- lapply(res,function(x){sprintf("%03d",x)})	
    }
    
    ## make changes permanent by saving updated 'collections' dataset in 
    ## opts$auxPath
    save(MODIScollection, file = fls_col)
    
return(res)
}

