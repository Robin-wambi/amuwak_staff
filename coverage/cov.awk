/^SF:/ { f=substr($0,4); next }
/^DA:/ {
  split(substr($0,4),a,","); line=a[1]; hit=a[2]+0;
  key=f"|"line;
  if (!(key in seen)) { seen[key]=1; lf[f]++; }
  if (hit>cov[key]) cov[key]=hit;
}
END {
  for (k in cov) if (cov[k]>0) { split(k,p,"|"); lh[p[1]]++; }
  for (file in lf) {
    pct = lh[file]*100.0/lf[file];
    printf "%6.1f%%  %4d/%-4d  %s\n", pct, lh[file]+0, lf[file], file;
  }
}
