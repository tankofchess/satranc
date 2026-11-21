#include <bits/stdc++.h>
using namespace std;

// K+R+A vs K icin kesin DTM tablosu (ply). Bitboard hizlandirmali retrograd analiz.
// index = ((((wk*64 + bk)*64 + rs)*64 + ns)*2 + stm); stm 0=beyaz, 1=siyah.
static const int N = 64*64*64*64*2;
static vector<uint8_t> res(N, 0), rem(N, 0);
static uint64_t adjM[64], btw[64][64], knightM[64];
static bool rAlign[64][64];
static int kingMv[64][8], kingCnt[64];
static int rookMv[64][28], rookCnt[64];
static int knightMv[64][8], knightCnt[64];

inline int idx(int wk,int bk,int rs,int ns,int stm){
  return ((((wk*64+bk)*64+rs)*64+ns)*2+stm);
}
inline int f(int s){ return s&7; }
inline int r(int s){ return s>>3; }
inline uint64_t bit(int s){ return 1ULL<<s; }
inline bool adj(int a,int b){ return abs(f(a)-f(b))<=1 && abs(r(a)-r(b))<=1; }
inline bool okSq(int wk,int bk,int rs,int ns){
  return wk!=bk && wk!=rs && wk!=ns && bk!=rs && bk!=ns && rs!=ns && !adj(wk,bk);
}

void init(){
  for(int a=0;a<64;a++) for(int b=0;b<64;b++){
    if(a==b) continue;
    int df=f(b)-f(a), dr=r(b)-r(a);
    if(adj(a,b)) adjM[a] |= bit(b);
    bool rank=dr==0, file=df==0;
    if(rank||file){
      rAlign[a][b]=true;
      int sf=(df>0)-(df<0), sr=(dr>0)-(dr<0);
      int x=f(a)+sf, y=r(a)+sr;
      while(x!=f(b) || y!=r(b)){ btw[a][b] |= bit(y*8+x); x+=sf; y+=sr; }
    }
  }
  static const int K[8][2]={{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}};
  static const int RD[4][2]={{1,0},{-1,0},{0,1},{0,-1}};
  static const int ND[8][2]={{1,2},{2,1},{2,-1},{1,-2},{-1,-2},{-2,-1},{-2,1},{-1,2}};
  for(int s=0;s<64;s++){
    for(auto&d:K){ int x=f(s)+d[0],y=r(s)+d[1];
      if(x>=0&&x<8&&y>=0&&y<8) kingMv[s][kingCnt[s]++]=y*8+x; }
    for(auto&d:RD){ int x=f(s)+d[0],y=r(s)+d[1];
      while(x>=0&&x<8&&y>=0&&y<8){ rookMv[s][rookCnt[s]++]=y*8+x; x+=d[0]; y+=d[1]; } }
    for(auto&d:ND){ int x=f(s)+d[0],y=r(s)+d[1];
      if(x>=0&&x<8&&y>=0&&y<8){ knightMv[s][knightCnt[s]++]=y*8+x; knightM[s] |= bit(y*8+x); } }
  }
}

// ignoreBK>=0 ise o kare engel sayilmaz (sah kacarken).
inline bool attacked(int target,int wk,int rs,int ns,int ignoreBK){
  if(adjM[wk] & bit(target)) return true;
  if(knightM[ns] & bit(target)) return true;
  uint64_t blockers = bit(wk)|bit(rs)|bit(ns);
  if(ignoreBK>=0) blockers |= bit(ignoreBK);
  if(rAlign[rs][target] && (btw[rs][target] & blockers)==0) return true;
  return false;
}

inline void genBlack(int wk,int bk,int rs,int ns, int* out, int& n){
  n=0;
  for(int i=0;i<kingCnt[bk];i++){
    int nb=kingMv[bk][i];
    if(nb==wk) continue;
    if(nb==rs || nb==ns){ if(!attacked(nb,wk,rs,ns,-1)) out[n++]=nb; continue; }
    if(!okSq(wk,nb,rs,ns)) continue;
    if(attacked(nb,wk,rs,ns,-1)) continue;
    out[n++]=nb;
  }
}

int main(int argc,char**argv){
  const char* outFile = argc>1 ? argv[1] : "/tmp/opencode/krn.dat";
  auto t0=chrono::steady_clock::now();
  init();
  int mvBuf[16];
  for(int wk=0;wk<64;wk++) for(int bk=0;bk<64;bk++)
  for(int rs=0;rs<64;rs++) for(int ns=0;ns<64;ns++){
    if(!okSq(wk,bk,rs,ns)) continue;
    int n; genBlack(wk,bk,rs,ns,mvBuf,n);
    rem[idx(wk,bk,rs,ns,1)] = (uint8_t)n;
    if(n==0 && attacked(bk,wk,rs,ns,-1)) res[idx(wk,bk,rs,ns,1)] = 1;
  }
  vector<int> q; q.reserve(20000000);
  for(int i=0;i<N;i++) if(res[i]) q.push_back(i);
  cerr<<"KRN mates="<<q.size()<<" init="<<chrono::duration<double>(chrono::steady_clock::now()-t0).count()<<"s\n";

  size_t head=0;
  while(head<q.size()){
    int cur=q[head++];
    uint8_t d=res[cur];
    int stm=cur&1;
    int t=cur>>1;
    int ns=t&63; t>>=6;
    int rs=t&63; t>>=6;
    int bk=t&63; t>>=6;
    int wk=t&63;

    if(stm==1){
      // Beyazin onceki hamlesi.
      for(int i=0;i<kingCnt[wk];i++){
        int owk=kingMv[wk][i];
        if(!okSq(owk,bk,rs,ns)) continue;
        if(attacked(bk,owk,rs,ns,-1)) continue;
        int pi=idx(owk,bk,rs,ns,0);
        if(res[pi]==0){ res[pi]=d+1; q.push_back(pi); }
      }
      uint64_t occR = bit(wk)|bit(bk)|bit(ns);
      for(int i=0;i<rookCnt[rs];i++){
        int ors=rookMv[rs][i];
        if(ors==wk||ors==bk||ors==ns) continue;
        if(btw[ors][rs] & occR) continue;
        if(attacked(bk,wk,ors,ns,-1)) continue;
        int pi=idx(wk,bk,ors,ns,0);
        if(res[pi]==0){ res[pi]=d+1; q.push_back(pi); }
      }
      uint64_t occN = bit(wk)|bit(bk)|bit(rs);
      for(int i=0;i<knightCnt[ns];i++){
        int ons=knightMv[ns][i];   // at hareketi simetriktir
        if(ons==wk||ons==bk||ons==rs) continue;
        if(attacked(bk,wk,rs,ons,-1)) continue;
        int pi=idx(wk,bk,rs,ons,0);
        if(res[pi]==0){ res[pi]=d+1; q.push_back(pi); }
      }
    } else {
      // Siyahin onceki hamlesi: sah obk'den bk'ye gelir.
      for(int i=0;i<kingCnt[bk];i++){
        int obk=kingMv[bk][i];
        if(obk==wk||obk==rs||obk==ns) continue;
        if(!okSq(wk,obk,rs,ns)) continue;
        if(attacked(obk,wk,rs,ns,-1)) continue;
        if(attacked(bk,wk,rs,ns,obk)) continue;
        int pi=idx(wk,obk,rs,ns,1);
        if(res[pi]!=0 || rem[pi]==0) continue;
        if(--rem[pi]==0){ res[pi]=d+1; q.push_back(pi); }
      }
    }
  }
  unsigned long long legalW=0, legalB=0, nonWinW=0, illegalB=0, nonWinB=0;
  for(int wk=0;wk<64;wk++) for(int bk=0;bk<64;bk++)
  for(int rs=0;rs<64;rs++) for(int ns=0;ns<64;ns++){
    if(!okSq(wk,bk,rs,ns)) continue;
    if(!attacked(bk,wk,rs,ns,-1)){
      ++legalW;
      if(res[idx(wk,bk,rs,ns,0)]==0) ++nonWinW;
    }
    if(attacked(bk,wk,rs,ns,-1)){
      int n; genBlack(wk,bk,rs,ns,mvBuf,n);
      if(n>0) ++illegalB; else ++legalB;
    } else {
      ++legalB;
      if(res[idx(wk,bk,rs,ns,1)]==0) ++nonWinB;
    }
  }
  cerr<<"KRN legalW="<<legalW<<" legalB="<<legalB<<" illegalB="<<illegalB
      <<" nonWinW="<<nonWinW<<" nonWinB="<<nonWinB<<"\n";
  cerr<<"KRN states="<<q.size()
      <<" time="<<chrono::duration<double>(chrono::steady_clock::now()-t0).count()<<"s\n";
  FILE* fp=fopen(outFile,"wb"); fwrite(res.data(),1,N,fp); fclose(fp);
  return 0;
}
