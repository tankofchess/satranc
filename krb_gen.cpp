#include <bits/stdc++.h>
using namespace std;

// K+R+F vs K icin kesin DTM tablosu (ply). Bitboard hizlandirmali retrograd analiz.
// index = ((((wk*64 + bk)*64 + rs)*64 + bs)*2 + stm); stm 0=beyaz, 1=siyah.
static const int N = 64*64*64*64*2;
static vector<uint8_t> res(N, 0), rem(N, 0);
static uint64_t adjM[64], btw[64][64];
static bool rAlign[64][64], bAlign[64][64];
static int kingMv[64][8], kingCnt[64];
static int rookMv[64][28], rookCnt[64];
static int bishopMv[64][28], bishopCnt[64];

inline int idx(int wk,int bk,int rs,int bs,int stm){
  return ((((wk*64+bk)*64+rs)*64+bs)*2+stm);
}
inline int f(int s){ return s&7; }
inline int r(int s){ return s>>3; }
inline uint64_t bit(int s){ return 1ULL<<s; }
inline bool adj(int a,int b){ return abs(f(a)-f(b))<=1 && abs(r(a)-r(b))<=1; }
inline bool okSq(int wk,int bk,int rs,int bs){
  return wk!=bk && wk!=rs && wk!=bs && bk!=rs && bk!=bs && rs!=bs && !adj(wk,bk);
}

void init(){
  for(int a=0;a<64;a++) for(int b=0;b<64;b++){
    if(a==b) continue;
    int df=f(b)-f(a), dr=r(b)-r(a);
    if(adj(a,b)) adjM[a] |= bit(b);
    bool rank=dr==0, file=df==0, diag=abs(df)==abs(dr);
    rAlign[a][b] = rank||file;
    bAlign[a][b] = diag && !rank && !file;
    if(rAlign[a][b] || bAlign[a][b]){
      int sf=(df>0)-(df<0), sr=(dr>0)-(dr<0);
      int x=f(a)+sf, y=r(a)+sr;
      while(x!=f(b) || y!=r(b)){ btw[a][b] |= bit(y*8+x); x+=sf; y+=sr; }
    }
  }
  static const int K[8][2]={{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}};
  static const int RD[4][2]={{1,0},{-1,0},{0,1},{0,-1}};
  static const int BD[4][2]={{1,1},{1,-1},{-1,1},{-1,-1}};
  for(int s=0;s<64;s++){
    for(auto&d:K){ int x=f(s)+d[0],y=r(s)+d[1];
      if(x>=0&&x<8&&y>=0&&y<8) kingMv[s][kingCnt[s]++]=y*8+x; }
    for(auto&d:RD){ int x=f(s)+d[0],y=r(s)+d[1];
      while(x>=0&&x<8&&y>=0&&y<8){ rookMv[s][rookCnt[s]++]=y*8+x; x+=d[0]; y+=d[1]; } }
    for(auto&d:BD){ int x=f(s)+d[0],y=r(s)+d[1];
      while(x>=0&&x<8&&y>=0&&y<8){ bishopMv[s][bishopCnt[s]++]=y*8+x; x+=d[0]; y+=d[1]; } }
  }
}

// ignoreBK>=0 ise o kare engel sayilmaz (sah kacarken).
inline bool attacked(int target,int wk,int rs,int bs,int ignoreBK){
  if(adjM[wk] & bit(target)) return true;
  uint64_t blockers = bit(wk)|bit(rs)|bit(bs);
  if(ignoreBK>=0) blockers |= bit(ignoreBK);
  if(rAlign[rs][target] && (btw[rs][target] & blockers)==0) return true;
  if(bAlign[bs][target] && (btw[bs][target] & blockers)==0) return true;
  return false;
}

inline void genBlack(int wk,int bk,int rs,int bs, int* out, int& n){
  n=0;
  for(int i=0;i<kingCnt[bk];i++){
    int nb=kingMv[bk][i];
    if(nb==wk) continue;
    if(nb==rs || nb==bs){ if(!attacked(nb,wk,rs,bs,-1)) out[n++]=nb; continue; }
    if(!okSq(wk,nb,rs,bs)) continue;
    if(attacked(nb,wk,rs,bs,-1)) continue;
    out[n++]=nb;
  }
}

int main(int argc,char**argv){
  const char* outFile = argc>1 ? argv[1] : "/tmp/opencode/krb.dat";
  auto t0=chrono::steady_clock::now();
  init();
  int mvBuf[16];
  for(int wk=0;wk<64;wk++) for(int bk=0;bk<64;bk++)
  for(int rs=0;rs<64;rs++) for(int bs=0;bs<64;bs++){
    if(!okSq(wk,bk,rs,bs)) continue;
    int n; genBlack(wk,bk,rs,bs,mvBuf,n);
    rem[idx(wk,bk,rs,bs,1)] = (uint8_t)n;
    if(n==0 && attacked(bk,wk,rs,bs,-1)) res[idx(wk,bk,rs,bs,1)] = 1;
  }
  vector<int> q; q.reserve(20000000);
  for(int i=0;i<N;i++) if(res[i]) q.push_back(i);
  cerr<<"KRB mates="<<q.size()<<" init="<<chrono::duration<double>(chrono::steady_clock::now()-t0).count()<<"s\n";

  size_t head=0;
  while(head<q.size()){
    int cur=q[head++];
    uint8_t d=res[cur];
    int stm=cur&1;
    int t=cur>>1;
    int bs=t&63; t>>=6;
    int rs=t&63; t>>=6;
    int bk=t&63; t>>=6;
    int wk=t&63;

    if(stm==1){
      // Beyazin onceki hamlesi.
      for(int i=0;i<kingCnt[wk];i++){
        int owk=kingMv[wk][i];
        if(!okSq(owk,bk,rs,bs)) continue;
        if(attacked(bk,owk,rs,bs,-1)) continue;
        int pi=idx(owk,bk,rs,bs,0);
        if(res[pi]==0){ res[pi]=d+1; q.push_back(pi); }
      }
      uint64_t occR = bit(wk)|bit(bk)|bit(bs);
      for(int i=0;i<rookCnt[rs];i++){
        int ors=rookMv[rs][i];
        if(ors==wk||ors==bk||ors==bs) continue;
        if(btw[ors][rs] & occR) continue;
        if(attacked(bk,wk,ors,bs,-1)) continue;
        int pi=idx(wk,bk,ors,bs,0);
        if(res[pi]==0){ res[pi]=d+1; q.push_back(pi); }
      }
      uint64_t occB = bit(wk)|bit(bk)|bit(rs);
      for(int i=0;i<bishopCnt[bs];i++){
        int obs=bishopMv[bs][i];
        if(obs==wk||obs==bk||obs==rs) continue;
        if(btw[obs][bs] & occB) continue;
        if(attacked(bk,wk,rs,obs,-1)) continue;
        int pi=idx(wk,bk,rs,obs,0);
        if(res[pi]==0){ res[pi]=d+1; q.push_back(pi); }
      }
    } else {
      // Siyahin onceki hamlesi: sah obk'den bk'ye gelir, obk bosalir.
      for(int i=0;i<kingCnt[bk];i++){
        int obk=kingMv[bk][i];
        if(obk==wk||obk==rs||obk==bs) continue;
        if(!okSq(wk,obk,rs,bs)) continue;
        if(attacked(obk,wk,rs,bs,-1)) continue;       // onceki konum yasal olmali
        if(attacked(bk,wk,rs,bs,obk)) continue;       // obk bosaldi, sah acikta kalmamali
        int pi=idx(wk,obk,rs,bs,1);
        if(res[pi]!=0 || rem[pi]==0) continue;
        if(--rem[pi]==0){ res[pi]=d+1; q.push_back(pi); }
      }
    }
  }
  cerr<<"KRB states="<<q.size()
      <<" time="<<chrono::duration<double>(chrono::steady_clock::now()-t0).count()<<"s\n";
  FILE* fp=fopen(outFile,"wb"); fwrite(res.data(),1,N,fp); fclose(fp);
  return 0;
}
