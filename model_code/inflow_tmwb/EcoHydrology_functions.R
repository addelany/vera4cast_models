#adjusting ecohydrology package functions because keep getting following error:
#Error in Tx == -999 || Tn == -999 : 'length = 2922' in coercion to 'logical(1)'
#15Apr2024


pet_fromTemp <- function (Jday, Tmax_C, Tmin_C, lat_radians, AvgT = (Tmax_C + Tmin_C)/2, albedo = 0.18, TerrestEmiss = 0.97, aspect = 0, slope = 0, forest = 0, PTconstant=1.26, AEparams=list(vp=NULL, opt="linear")) 
{
  if (length(Jday) != length(Tmax_C) | length(Jday) != length(Tmin_C)) {
    cat("Warning, input vectors unequal length:  Longer data sets truncated.\n")
    length(Jday) <- min(length(Jday), length(Tmax_C), length(Tmin_C))
    length(Tmax_C) <- min(length(Jday), length(Tmax_C), length(Tmin_C))
    length(Tmin_C) <- min(length(Jday), length(Tmax_C), length(Tmin_C))
  }
  cloudiness <- clouds(Tmax_C, Tmin_C)
  DailyRad <- NetRad(lat_radians, Jday, Tmax_C, Tmin_C, albedo, forest, slope, aspect, AvgT, cloudiness, TerrestEmiss, AvgT, AEparams=AEparams)
  
  potentialET <- PTpet(DailyRad, AvgT, PTconstant)
  potentialET[which(potentialET < 0)] <- 0
  potentialET[which(Tmax_C == -999 | Tmin_C == -999)] <- (-999)
  return(potentialET)
}


clouds <- function (Tx=(-999), Tn=(-999), trans=NULL, transMin = 0.15, transMax = 0.75, opt = "linear") {
  suppressWarnings(if (any(Tx == -999 | Tn == -999) & is.null(trans)){ 
    print("Error: Please enter either Max&Min temp or transmissivity")
  } else {
    if (is.null(trans))	trans <- transmissivity(Tx, Tn)
    if (opt=="Black") {
      cl <- (0.34 - sqrt(0.34^2 + 4*0.458*(0.803-trans)))/(-2*0.458)
      cl[which(trans > 0.803)] <- 0
    } else {
      cl <- 1 - (trans-transMin) / (transMax-transMin)
    }
    cl[which(cl > 1)] <- 1
    cl[which(cl < 0)] <- 0
    return(cl)
  } )
}

snowmelt <- function(Date, precip_mm, Tmax_C, Tmin_C, lat_deg, slope=0, aspect=0, tempHt=1, windHt=2, groundAlbedo=0.25, 		SurfEmissiv=0.95, windSp=2, forest=0, startingSnowDepth_m=0, startingSnowDensity_kg_m3=450){	
  ## Constants :
  WaterDens <- 1000			# kg/m3
  lambda <- 3.35*10^5			# latent heat of fusion (kJ/m3)
  lambdaV <- 2500				# (kJ/kg) latent heat of vaporization
  SnowHeatCap <- 2.1			# kJ/kg/C
  LatHeatFreez <- 333.3		# kJ/kg
  Cw <- 4.2*10^3				# Heat Capacity of Water (kJ/m3/C)
  
  ##	Converted Inputs :
  Tav <- (Tmax_C+Tmin_C)/2		# degrees C
  precip_m <- precip_mm*0.001	 	# precip in m 
  R_m <- precip_m					# (m) depth of rain
  R_m[which(Tav < 0)] <- 0		# ASSUMES ALL SNOW at < 0C
  NewSnowDensity <- 50+3.4*(Tav+15)		# kg/m3
  NewSnowDensity[which(NewSnowDensity < 50)] <- 50
  NewSnowWatEq <- precip_m				# m
  NewSnowWatEq[which(Tav >= 0)] <- 0			# No new snow if average temp above or equals 0 C
  NewSnow <- NewSnowWatEq*WaterDens/NewSnowDensity		# m
  JDay <- strptime(Date, format="%Y-%m-%d")$yday+1
  lat <- lat_deg*pi/180		#	latitude in radians
  rh 	<- log((windHt+0.001)/0.001)*log((tempHt+0.0002)/0.0002)/(0.41*0.41*windSp*86400)	# (day/m) Thermal Resistance	 
  if (length(windSp)==1) rh <- rep(rh,length(precip_mm))									##	creates a vector of rh values
  cloudiness 		<- clouds(Tmax_C,Tmin_C)
  AE 				<- AtmosphericEmissivity(Tav, cloudiness)	# (-) Atmospheric Emissivity
  
  #  New Variables	:
  SnowTemp 		<- rep(0,length(precip_m)) 		# Degrees C
  rhos 			<- SatVaporDensity(SnowTemp)	# 	vapor density at surface (kg/m3)
  rhoa 			<- SatVaporDensity(Tmin_C)		#	vapor density of atmoshpere (kg/m3) 
  SnowWaterEq 	<- vector(length=length(precip_mm))		#  (m) Equiv depth of water
  TE 				<- rep(SurfEmissiv,length(precip_mm))	#	(-) Terrestrial Emissivity
  DCoef 			<- rep(0,length(precip_mm))				#   Density Coefficient (-) (Simplified version)
  SnowDensity 	<- rep(450,length(precip_mm))			#  (kg/m3)  Max density is 450
  SnowDepth 		<- vector(length=length(precip_mm))		#  (m)
  SnowMelt 		<- rep(0,length(precip_mm))				#  (m)
  Albedo 			<- rep(groundAlbedo,length(precip_mm)) 	#  (-) This will change for days with snow
  
  ##	Energy Terms
  H 		<- vector(length=length(precip_mm))	#	Sensible Heat exchanged (kJ/m2/d)
  E 		<- vector(length=length(precip_mm))	#	Vapor Energy	(kJ/m2/d)
  S 		<- vector(length=length(precip_mm))	#	Solar Radiation (kJ/m2/d)
  La 		<- Longwave(AE, Tav)					#	Atmospheric Longwave Radiation (kJ/m2/d)
  Lt 		<- vector(length=length(precip_mm))	#	Terrestrial Longwave Radiation (kJ/m2/d)
  G 		<- 173								#	Ground Condution (kJ/m2/d) 
  P 		<- Cw * R_m * Tav					# 	Precipitation Heat (kJ/m2/d)
  Energy 	<- vector(length=length(precip_mm))	# Net Energy (kJ/m2/d)
  
  ##  Initial Values.  
  SnowWaterEq[1] 	<- startingSnowDepth_m * startingSnowDensity_kg_m3 / WaterDens		
  SnowDepth[1] 	<- startingSnowDepth_m			
  Albedo[1] <- ifelse(NewSnow[1] > 0, 0.98-(0.98-0.50)*exp(-4*NewSnow[1]*10),ifelse(startingSnowDepth_m == 0, groundAlbedo, max(groundAlbedo, 0.5+(groundAlbedo-0.85)/10)))  # If snow on the ground or new snow, assume Albedo yesterday was 0.5
  S[1] <- Solar(lat=lat,Jday=JDay[1], Tx=Tmax_C[1], Tn=Tmin_C[1], albedo=Albedo[1], forest=forest, aspect=aspect, slope=slope)
  H[1] <- 1.29*(Tav[1]-SnowTemp[1])/rh[1] 
  E[1] <- lambdaV*(rhoa[1]-rhos[1])/rh[1]
  if(startingSnowDepth_m>0) TE[1] <- 0.97 
  Lt[1] <- Longwave(TE[1],SnowTemp[1])
  Energy[1] <- S[1] + La[1] - Lt[1] + H[1] + E[1] + G + P[1]
  SnowDensity[1] <- ifelse((startingSnowDepth_m+NewSnow[1])>0, min(450, (startingSnowDensity_kg_m3*startingSnowDepth_m + NewSnowDensity[1]*NewSnow[1])/(startingSnowDepth_m+NewSnow[1])), 450)
  SnowMelt[1] <- max(0,	min((startingSnowDepth_m/10+NewSnowWatEq[1]),  # yesterday on ground + today new  
                            (Energy[1]-SnowHeatCap*(startingSnowDepth_m/10+NewSnowWatEq[1])*WaterDens*(0-SnowTemp[1]))/(LatHeatFreez*WaterDens) ) )
  SnowDepth[1] <- max(0,(startingSnowDepth_m/10 + NewSnowWatEq[1]-SnowMelt[1])*WaterDens/SnowDensity[1])
  SnowWaterEq[1] <- max(0,startingSnowDepth_m/10-SnowMelt[1]+NewSnowWatEq[1])	
  
  
  
  ##  Snow Melt Loop	
  for (i in 2:length(precip_m)){
    if (NewSnow[i] > 0){ 
      Albedo[i] <- 0.98-(0.98-Albedo[i-1])*exp(-4*NewSnow[i]*10)
    } else if (SnowDepth[i-1] < 0.1){ 
      Albedo[i] <- max(groundAlbedo, Albedo[i-1]+(groundAlbedo-0.85)/10)
    } else Albedo[i] <- 0.35-(0.35-0.98)*exp(-1*(0.177+(log((-0.3+0.98)/(Albedo[i-1]-0.3)))^2.16)^0.46)
    
    S[i] <- Solar(lat=lat,Jday=JDay[i], Tx=Tmax_C[i], Tn=Tmin_C[i], albedo=Albedo[i-1], forest=forest, aspect=aspect, slope=slope, printWarn=FALSE)
    
    if(SnowDepth[i-1] > 0) TE[i] <- 0.97 	#	(-) Terrestrial Emissivity
    if(SnowWaterEq[i-1] > 0 | NewSnowWatEq[i] > 0) {
      DCoef[i] <- 6.2
      if(SnowMelt[i-1] == 0){ 
        SnowTemp[i] <- max(min(0,Tmin_C[i]),min(0,(SnowTemp[i-1]+min(-SnowTemp[i-1],Energy[i-1]/((SnowDensity[i-1]*
                                                                                                    SnowDepth[i-1]+NewSnow[i]*NewSnowDensity[i])*SnowHeatCap*1000)))))
      }
    }
    
    rhos[i] <- SatVaporDensity(SnowTemp[i])
    H[i] <- 1.29*(Tav[i]-SnowTemp[i])/rh[i] 
    E[i] <- lambdaV*(rhoa[i]-rhos[i])/rh[i]
    Lt[i] <- Longwave(TE[i],SnowTemp[i])
    Energy[i] <- S[i] + La[i] - Lt[i] + H[i] + E[i] + G + P[i]
    
    if (Energy[i]>0) k <- 2 else k <- 1
    
    SnowDensity[i] <- ifelse((SnowDepth[i-1]+NewSnow[i])>0, min(450, 
                                                                ((SnowDensity[i-1]+k*30*(450-SnowDensity[i-1])*exp(-DCoef[i]))*SnowDepth[i-1] + NewSnowDensity[i]*NewSnow[i])/(SnowDepth[i-1]+NewSnow[i])), 450)
    
    SnowMelt[i] <- max(0,	min( (SnowWaterEq[i-1]+NewSnowWatEq[i]),  # yesterday on ground + today new
                               (Energy[i]-SnowHeatCap*(SnowWaterEq[i-1]+NewSnowWatEq[i])*WaterDens*(0-SnowTemp[i]))/(LatHeatFreez*WaterDens) )  )
    
    SnowDepth[i] <- max(0,(SnowWaterEq[i-1]+NewSnowWatEq[i]-SnowMelt[i])*WaterDens/SnowDensity[i])
    SnowWaterEq[i] <- max(0,SnowWaterEq[i-1]-SnowMelt[i]+NewSnowWatEq[i])	# (m) Equiv depth of water
  }
  
  Results<-data.frame(Date, Tmax_C, Tmin_C, precip_mm, R_m*1000, NewSnowWatEq*1000,SnowMelt*1000, NewSnow, SnowDepth, SnowWaterEq*1000)
  colnames(Results)<-c("Date", "MaxT_C", "MinT_C", "Precip_mm", "Rain_mm", "SnowfallWatEq_mm", "SnowMelt_mm", "NewSnow_m", "SnowDepth_m", "SnowWaterEq_mm")
  return(Results)
}


get_usgs_gage <- function(flowgage_id,begin_date="1979-01-01",end_date="2013-01-01"){
  #
  # Grabs USGS stream flow data for 1979 to present... to align with CFSR datasets.
  #
  
  url = paste("http://waterdata.usgs.gov/nwis/inventory?search_site_no=", flowgage_id, "&search_site_no_match_type=exact&sort_key=site_no&group_key=NONE&format=sitefile_output&sitefile_output_format=rdb&column_name=station_nm&column_name=site_tp_cd&column_name=dec_lat_va&column_name=dec_long_va&column_name=alt_va&column_name=drain_area_va&column_name=contrib_drain_area_va&column_name=rt_bol&list_of_search_criteria=search_site_no",sep="")
  
  gage_tsv=readLines(url)
  gage_tsv=gage_tsv[grep("^#",gage_tsv,invert=T)][c(1,3)]
  tempdf=read.delim(text=gage_tsv,sep="\t",header=T,colClasses = c("character", "character", "numeric", "numeric", "character", "character", "numeric", "numeric", "character", "numeric"))
  area = tempdf$drain_area_va* 1.6^2
  if(is.na(area)) {area=0;print("warning, no area associated with gage, setting to 0\n")}
  declat = tempdf$dec_lat_va
  declon = tempdf$dec_long_va
  elev = tempdf$alt_va* 12/25.4
  if(is.na(elev)) {elev=0;print("warning, no elevation associated with gage, setting to 0\n")}
  
  gagename = tempdf$station_nm
  begin_date = as.character(begin_date)
  end_date = as.character(end_date)
  
  url = paste("http://nwis.waterdata.usgs.gov/nwis/dv?cb_00060=on&format=rdb&begin_date=",begin_date,"&end_date=",end_date,"&site_no=", flowgage_id, sep = "")
  flowdata_tsv=gage_tsv=readLines(url)
  flowdata_tsv=flowdata_tsv[grep("^#",flowdata_tsv,invert=T)][c(3:length(flowdata_tsv))]
  flowdata = read.delim(text=flowdata_tsv,header=F,sep="\t",col.names = c("agency", "site_no", "date", "flow", "quality"), colClasses = c("character", "numeric", "character", "character", "character"), fill = T)
  flowdata$mdate = as.Date(flowdata$date, format = "%Y-%m-%d")
  flowdata$flow = as.numeric(as.character(flowdata$flow)) * 12^3 * 2.54^3/100^3 * 24 * 3600
  flowdata = na.omit(flowdata)
  returnlist = list(declat = declat, declon = declon, flowdata = flowdata, area = area, elev = elev, gagename = gagename)
  return(returnlist)
  
}
