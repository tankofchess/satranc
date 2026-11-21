#include <bits/stdc++.h>
using namespace std;

// K+F+F vs K (zit renk filller) icin kesin DTM tablosu.
// b1 = acik renkli fil (parity 1), b2 = koyu renkli fil (parity 0).
// index = ((((wk*64 + bk)*64 + b1)*64 + b2)*2 + stm); stm 0=beyaz, 1=siyah.
static const int N = 64*64*64*64*2;
static vector<uint8_t> res(N, 0);
static vector<uint16_t> rem(N, 0);
static uint64_t adjM[64], btw[64][64];
static bool bAlign[64][64];
static int kingMv[64][8], kingCnt[64];
static int bishopMv[64][14], bishopCnt[64];

inline int idx(int wk,int bk,int b1,int b2,int stm){
  return ((((wk*64+bk)*64+b1)*64+b2)*2+stm);
}
inline int f(int s){ return s&7; }
inline int r(int s){ return s>>3; }
inline int parity(int s){ return (f(s)+r(s))&1; }
inline uint64_t bit(int s){ return 1ULL<<s; }
inline bool adj(int a,int b){ return abs(f(a)-f(b))<=1 && abs(r(a)-r(b))<=1; }

inline bool okSq(int wk,int bk,int b1,int b2){
  return wk!=bk && wk!=b1 && wk!=b2 && bk!=b1 && bk!=b2 && b1!=b2 &&
         !adj(wk,bk) && parity(b1)==1 && parity(b2)==0;
}

void init(){
  for(int a=0;a<64;a++) for(int b=0;b<64;b++){
    if(a==b) continue;
    if(adj(a,b)) adjM[a] |= bit(b);
    int df=f(b)-f(a), dr=r(b)-r(a);
    if(abs(df)==abs(dr) && df!=0){
      bAlign[a][b] = true;
      int sf=(df>0)-(df<0), sr=(dr>0)-(dr<0);
      int x=f(a)+sf, y=r(a)+sr;
      while(x!=f(b) || y!=r(b)){ btw[a][b] |= bit(y*8+x); x+=sf; y+=sr; }
    }
  }
  static const int K[8][2]={{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}};
  static const int BD[4][2]={{1,1},{1,-1},{-1,1},{-1,-1}};
  for(int s=0;s<64;s++){
    for(auto&d:K){ int x=f(s)+d[0],y=r(s)+d[1];
      if(x>=0&&x<8&&y>=0&&y<8) kingMv[s][kingCnt[s]++]=y*8+x; }
    for(auto&d:BD){ int x=f(s)+d[0],y=r(s)+d[1];
      while(x>=0&&x<8&&y>=0&&y<8){ bishopMv[s][bishopCnt[s]++]=y*8+x; x+=d[0]; y+=d[1]; } }
  }
}

// extraBlocker >=0: o kare dolu sayilir (sah eski karesi).
// skipBishop 1=b1'i, 2=b2'yi devre disi birakir (o fil yeni alindi).
inline bool attacked(int target,int wk,int b1,int b2,int extraBlocker,int skipBishop){
  if(adjM[wk] & bit(target)) return true;
  uint64_t blockers = bit(wk);
  if(b1>=0 && skipBishop!=1) blockers |= bit(b1);
  if(b2>=0 && skipBishop!=2) blockers |= bit(b2);
  if(extraBlocker>=0) blockers |= bit(extraBlocker);
  if(b1>=0 && skipBishop!=1 && bAlign[b1][target] && (btw[b1][target] & blockers)==0) return true;
  if(b2>=0 && skipBishop!=2 && bAlign[b2][target] && (btw[b2][target] & blockers)==0) return true;
  return false;
}

inline void genBlack(int wk,int bk,int b1,int b2,int* out,int& n,int& captures){
  n=0; captures=0;
  for(int i=0;i<kingCnt[bk];i++){
    int nb=kingMv[bk][i];
    if(nb==wk) continue;
    if(nb==b1){
      if(!attacked(nb, wk, -1, b2, bk, 1)){ out[n++]=nb; captures++; }
      continue;
    }
    if(nb==b2){
      if(!attacked(nb, wk, b1, -1, bk, 2)){ out[n++]=nb; captures++; }
      continue;
    }
    if(!okSq(wk,nb,b1,b2)) continue;
    if(attacked(nb, wk, b1, b2, bk, 0)) continue;
    out[n++]=nb;
  }
}

int main(int argc,char**argv){
  const char* outFile = argc>1 ? argv[1] : "/tmp/opencode/kbb.dat";
  auto t0=chrono::steady_clock::now();
  init();
  int mv[16];

  for(int wk=0;wk<64;wk++) for(int bk=0;bk<64;bk++)
  for(int b1=0;b1<64;b1++) for(int b2=0;b2<64;b2++){
    if(!okSq(wk,bk,b1,b2)) continue;
    int n, cap; genBlack(wk,bk,b1,b2,mv,n,cap);
    int pi = idx(wk,bk,b1,b2,1);
    rem[pi] = (uint16_t)(n - cap + (cap>0 ? 1000 : 0));
    if(n==0 && attacked(bk,wk,b1,b2,-1,0)) res[pi] = 1;
  }

  vector<int> q; q.reserve(2000000);
  for(int i=0;i<N;i++) if(res[i]) q.push_back(i);
  cerr<<"KBB mates="<<q.size()<<" init="<<chrono::duration<double>(chrono::steady_clock::now()-t0).count()<<"s\n";

  size_t head=0;
  while(head<q.size()){
    int cur=q[head++];
    uint8_t d=res[cur];
    int stm=cur&1;
    int t=cur>>1;
    int b2=t&63; t>>=6;
    int b1=t&63; t>>=6;
    int bk=t&63; t>>=6;
    int wk=t&63;

    if(stm==1){
      // Beyazin onceki hamlesi -> simdi siyah hamlesi (mat veya kayip).
      for(int i=0;i<kingCnt[wk];i++){
        int owk=kingMv[wk][i];
        if(!okSq(owk,bk,b1,b2)) continue;
        if(attacked(bk,owk,b1,b2,-1,0)) continue;
        int pi=idx(owk,bk,b1,b2,0);
        if(res[pi]==0){ res[pi]=d+1; q.push_back(pi); }
      }
      uint64_t blockersB1 = bit(wk)|bit(bk)|bit(b2);
      for(int i=0;i<bishopCnt[b1];i++){
        int ob1=bishopMv[b1][i];
        if(ob1==wk||ob1==bk||ob1==b2) continue;
        if(btw[ob1][b1] & blockersB1) continue;
        if(!okSq(wk,bk,ob1,b2)) continue;
        if(attacked(bk,wk,ob1,b2,-1,0)) continue;
        int pi=idx(wk,bk,ob1,b2,0);
        if(res[pi]==0){ res[pi]=d+1; q.push_back(pi); }
      }
      uint64_t blockersB2 = bit(wk)|bit(bk)|bit(b1);
      for(int i=0;i<bishopCnt[b2];i++){
        int ob2=bishopMv[b2][i];
        if(ob2==wk||ob2==bk||ob2==b1) continue;
        if(btw[ob2][b2] & blockersB2) continue;
        if(!okSq(wk,bk,b1,ob2)) continue;
        if(attacked(bk,wk,b1,ob2,-1,0)) continue;
        int pi=idx(wk,bk,b1,ob2,0);
        if(res[pi]==0){ res[pi]=d+1; q.push_back(pi); }
      }
    } else {
      // Siyahin onceki hamlesi: obk'den bk'ye geldi. obk dolu kareydi.
      for(int i=0;i<kingCnt[bk];i++){
        int obk=kingMv[bk][i];
        if(obk==wk||obk==b1||obk==b2) continue;
        if(!okSq(wk,obk,b1,b2)) continue;
        if(attacked(bk,wk,b1,b2,obk,0)) continue;
        int pi=idx(wk,obk,b1,b2,1);
        if(res[pi]!=0 || rem[pi]==0) continue;
        if(--rem[pi]==0){ res[pi]=d+1; q.push_back(pi); }
      }
    }
  }

  int mx=0, nz=0;
  for(int i=0;i<N;i++) if(res[i]){ nz++; if(res[i]>mx) mx=res[i]; }
  cerr<<"KBB states="<<nz<<" maxDTM="<<mx
      <<" time="<<chrono::duration<double>(chrono::steady_clock::now()-t0).count()<<"s\n";
  FILE* fp=fopen(outFile,"wb"); fwrite(res.data(),1,N,fp); fclose(fp);
  return 0;
}
