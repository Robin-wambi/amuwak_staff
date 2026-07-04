/^SF:/ { f=substr($0,4); gsub("\\\\","/",f); next }
/^DA:/ {
  split(substr($0,4),a,","); line=a[1]; hit=a[2]+0;
  key=f"|"line;
  if (hit>cov[key]) cov[key]=hit;
  if (!(key in seen)) seen[key]=1;
}
END {
  for (k in seen) { split(k,p,"|"); if (cov[k]==0 && p[1]==TARGET) print p[2]; }
}
