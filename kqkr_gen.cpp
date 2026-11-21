#include <bits/stdc++.h>
using namespace std;

// K+V vs K+R kesin tablosu (isaretli DTM).
//   > 0 : normalize beyaz (vezir tarafi) N yari hamlede mat zorlar
//   < 0 : normalize siyah (kale tarafi) -N yari hamlede mat zorlar
//   0   : beraberlik / zorla mat yok
// index = ((((wk*64 + bk)*64 + wq)*64 + br)*2 + stm)
static const int N = 64*64*64*64*2;
static vector<int16_t> res(N, 0);
static vector<uint8_t> rem(N, 0), legal(N, 0), viaCap(N, 0);
static vector<int8_t> kqt, krt;
static const int K[8][2]={{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}};
static const int QD[8][2]={{1,0},{-1,0},{0,1},{0,-1},{1,1},{1,-1},{-1,1},{-1,-1}};
static const int RD[4][2]={{1,0},{-1,0},{0,1},{0,-1}};

inline int idx(int wk,int bk,int wq,int br,int stm){
  return ((((wk*64+bk)*64+wq)*64+br)*2+stm);
}
inline int sidx(int wk,int bk,int ps,int stm){
  return (((wk*64+bk)*64+ps)*2+stm);
}
inline int f(int s){ return s&7; }
inline int r(int s){ return s>>3; }
inline bool adj(int a,int b){ return abs(f(a)-f(b))<=1 && abs(r(a)-r(b))<=1; }
inline bool ok(int wk,int bk,int wq,int br){
  return wk!=bk && wk!=wq && wk!=br && bk!=wq && bk!=br && wq!=br && !adj(wk,bk);
}
inline bool rayHits(int from,int to,int wk,int bk,int blocker,int diag){
  int df=f(to)-f(from), dr=r(to)-r(from);
  bool rank = dr==0 && df!=0;
  bool file = df==0 && dr!=0;
  bool dg = diag && abs(df)==abs(dr) && df!=0;
  if(!(rank||file||dg)) return false;
  int sf=(df>0)-(df<0), sr=(dr>0)-(dr<0);
  int x=f(from)+sf, y=r(from)+sr;
  while(x!=f(to) || y!=r(to)){
    int s=y*8+x;
    if(s==wk || s==bk || s==blocker) return false;
    x+=sf; y+=sr;
  }
  return true;
}
// t nin beyaz(lar) tarafindan saldirilmasi: kral veya vezir
inline bool whiteAttack(int t,int wk,int wq,int bk,int br){
  if(t==wk || t==wq) return false;
  if(adj(t,wk)) return true;
  return rayHits(wq,t,wk,bk,br,true);
}
// t nin siyah(lar) tarafindan saldirilmasi: kral veya kale
inline bool blackAttack(int t,int bk,int br,int wk,int wq){
  if(t==bk || t==br) return false;
  if(adj(t,bk)) return true;
  return rayHits(br,t,bk,wk,wq,false);
}
// siyah sah beyaz vezir tarafindan saldiriliyor mu (mat/legal icin)
inline bool blackKingInCheck(int wk,int wq,int bk,int br){
  return rayHits(wq,bk,wk,bk,br,true);   // wk ile bk yan yana degil
}
// beyaz sah siyah kale tarafindan saldiriliyor mu
inline bool whiteKingInCheck(int wk,int wq,int bk,int br){
  return rayHits(br,wk,bk,wk,wq,false);
}

struct Child { int state; };
struct Capt { int val; }; // pozitif = beyaz kazanir, negatif = siyah kazanir

// Beyaz hamleleri: legal cocuklar + terminal yakalamalar.
inline void genWhite(int wk,int bk,int wq,int br, vector<int>& ch, vector<int>& caps, int& capCount){
  ch.clear(); caps.clear(); capCount=0;
  for(auto&d:K){
    int x=f(wk)+d[0], y=r(wk)+d[1];
    if(x<0||x>7||y<0||y>7) continue;
    int nw=y*8+x;
    if(nw==bk || nw==wq) continue;
    if(adj(nw,bk)) continue; // kale krali koruyorsa yakalama yasal degil
    if(nw==br){
      capCount++;
      int kd=kqt[sidx(nw,bk,wq,1)];       // K+V vs K, siyah hamle
      if(kd>0) caps.push_back(1+kd);
      continue;
    }
    if(adj(nw,bk)) continue;
    if(blackAttack(nw,bk,br,nw,wq)) continue; // kral yuruyunce eski kare bosalir
    int ci=idx(nw,bk,wq,br,1);
    if(legal[ci]) ch.push_back(ci);
  }
  for(auto&d:QD){
    int x=f(wq)+d[0], y=r(wq)+d[1];
    while(x>=0&&x<=7&&y>=0&&y<=7){
      int s=y*8+x;
      if(s==wk || s==bk) break;
      if(s==br){
        capCount++;
        int kd=kqt[sidx(wk,bk,s,1)];
        if(kd>0) caps.push_back(1+kd);
        break;
      }
      int ci=idx(wk,bk,s,br,1);
      if(legal[ci]) ch.push_back(ci);
      x+=d[0]; y+=d[1];
    }
  }
}

// Siyah hamleleri: legal cocuklar + terminal yakalamalar (negatif deger).
inline void genBlack(int wk,int bk,int wq,int br, vector<int>& ch, vector<int>& caps, int& capCount){
  ch.clear(); caps.clear(); capCount=0;
  for(auto&d:K){
    int x=f(bk)+d[0], y=r(bk)+d[1];
    if(x<0||x>7||y<0||y>7) continue;
    int nb=y*8+x;
    if(nb==wk || nb==br) continue;
    if(adj(nb,wk)) continue; // vezir krali koruyorsa yakalama yasal degil
    if(nb==wq){
      capCount++;
      int kd=krt[sidx(63-wq,63-wk,63-br,1)]; // aynalanmis K+R vs K
      if(kd>0) caps.push_back(-(1+kd));
      continue;
    }
    if(adj(nb,wk)) continue;
    if(whiteAttack(nb,wk,wq,nb,br)) continue; // eski sah karesi bosalir
    int ci=idx(wk,nb,wq,br,0);
    if(legal[ci]) ch.push_back(ci);
  }
  for(auto&d:RD){
    int x=f(br)+d[0], y=r(br)+d[1];
    while(x>=0&&x<=7&&y>=0&&y<=7){
      int s=y*8+x;
      if(s==bk || s==wk) break;
      if(s==wq){
        capCount++;
        int kd=krt[sidx(63-bk,63-wk,63-s,1)];
        if(kd>0) caps.push_back(-(1+kd));
        break;
      }
      int ci=idx(wk,bk,wq,s,0);
      if(legal[ci]) ch.push_back(ci);
      x+=d[0]; y+=d[1];
    }
  }
}

int main(){
  auto t0=chrono::steady_clock::now();
  FILE* fp=fopen("/tmp/opencode/kq.dat","rb");
  if(!fp){ fprintf(stderr,"kq.dat yok\n"); return 1; }
  kqt.resize(64*64*64*2); fread(kqt.data(),1,kqt.size(),fp); fclose(fp);
  fp=fopen("/tmp/opencode/kr.dat","rb");
  if(!fp){ fprintf(stderr,"kr.dat yok\n"); return 1; }
  krt.resize(64*64*64*2); fread(krt.data(),1,krt.size(),fp); fclose(fp);

  // 1) yasallik
  for(int wk=0;wk<64;wk++) for(int bk=0;bk<64;bk++)
  for(int wq=0;wq<64;wq++) for(int br=0;br<64;br++){
    if(!ok(wk,bk,wq,br)) continue;
    legal[idx(wk,bk,wq,br,0)] = !blackKingInCheck(wk,wq,bk,br) ? 1:0;
    legal[idx(wk,bk,wq,br,1)] = !whiteKingInCheck(wk,wq,bk,br) ? 1:0;
  }

  vector<int> ch, caps; ch.reserve(64); caps.reserve(4);
  int capCount=0;
  vector<vector<uint32_t>> buckets(512);
  long long initW=0, initB=0, stales=0;

  // 2) baslangic durumlari
  for(int wk=0;wk<64;wk++) for(int bk=0;bk<64;bk++)
  for(int wq=0;wq<64;wq++) for(int br=0;br<64;br++){
    if(!ok(wk,bk,wq,br)) continue;
    for(int stm=0;stm<2;stm++){
      int i=idx(wk,bk,wq,br,stm);
      if(!legal[i]) continue;
      if(stm==0) genWhite(wk,bk,wq,br,ch,caps,capCount);
      else       genBlack(wk,bk,wq,br,ch,caps,capCount);
      rem[i]=(uint8_t)min(ch.size()+(size_t)capCount,(size_t)255);
      int best=0;
      for(int c:caps){
        if(c>0 && (best==0 || c<best)) best=c;
        if(c<0 && (best==0 || c>best)) best=c;
      }
      if(best!=0){
        res[i]=best; viaCap[i]=1; buckets[abs(best)].push_back(i);
        if(best>0) initW++; else initB++;
        continue;
      }
      if(ch.empty() && capCount==0){
        bool inCheck = (stm==0) ? whiteKingInCheck(wk,wq,bk,br)
                                : blackKingInCheck(wk,wq,bk,br);
        if(inCheck){
          res[i] = (stm==0 ? -1 : 1);
          if(stm==0) initB++; else initW++;
        } else stales++;
      }
    }
  }
  cerr<<"init white="<<initW<<" black="<<initB<<" stalemate="<<stales<<"\n";

  // 3) retrograd yayilim
  for(int d=1; d<(int)buckets.size()-1; d++){
    for(uint32_t cur: buckets[d]){
      int16_t val=res[cur];
      if(abs((int)val)!=d) continue;
      int stm=cur&1;
      int t=cur>>1;
      int br=t&63; t>>=6;
      int wq=t&63; t>>=6;
      int bk=t&63; t>>=6;
      int wk=t&63;

      if(val>0){
        if(stm==1){
          // cur: siyah hamle, beyaz kazaniyor -> onceki BEYAZ hamlesi, herhangi bir
          // beyaz hamlesi bu duruma ulastigi icin onceki de beyaz kazanir.
          for(auto&dd:K){
            int x=f(wk)+dd[0], y=r(wk)+dd[1];
            if(x<0||x>7||y<0||y>7) continue;
            int owk=y*8+x;
            if(!ok(owk,bk,wq,br)) continue;
            int pi=idx(owk,bk,wq,br,0);
            if(!legal[pi]||res[pi]!=0) continue;
            res[pi]=d+1; buckets[d+1].push_back(pi);
          }
          for(auto&dd:QD){
            int x=f(wq)+dd[0], y=r(wq)+dd[1];
            while(x>=0&&x<=7&&y>=0&&y<=7){
              int owq=y*8+x;
              if(owq==wk||owq==bk||owq==br) break;
              int pi=idx(wk,bk,owq,br,0);
              if(legal[pi]&&res[pi]==0){
                res[pi]=d+1; buckets[d+1].push_back(pi);
              }
              x+=dd[0]; y+=dd[1];
            }
          }
        } else {
          // cur: beyaz hamle, beyaz kazaniyor -> onceki SIYAH hamlesi;
          // butun siyah hamleleri beyaz kazanca gidiyorsa onceki de beyaz kazanir.
          for(auto&dd:K){
            int x=f(bk)+dd[0], y=r(bk)+dd[1];
            if(x<0||x>7||y<0||y>7) continue;
            int obk=y*8+x;
            if(!ok(wk,obk,wq,br)) continue;
            int pi=idx(wk,obk,wq,br,1);
            if(!legal[pi]||res[pi]!=0||rem[pi]==0) continue;
            if(--rem[pi]==0){ res[pi]=d+1; buckets[d+1].push_back(pi); }
          }
          for(auto&dd:RD){
            int x=f(br)+dd[0], y=r(br)+dd[1];
            while(x>=0&&x<=7&&y>=0&&y<=7){
              int obr=y*8+x;
              if(obr==wk||obr==bk||obr==wq) break;
              int pi=idx(wk,bk,wq,obr,1);
              if(!legal[pi]||res[pi]!=0||rem[pi]==0){ x+=dd[0]; y+=dd[1]; continue; }
              if(--rem[pi]==0){ res[pi]=d+1; buckets[d+1].push_back(pi); }
              x+=dd[0]; y+=dd[1];
            }
          }
        }
      } else {
        if(stm==0){
          // cur: beyaz hamle, siyah kazaniyor -> onceki SIYAH hamlesi,
          // herhangi bir siyah hamlesi bu duruma ulastigi icin onceki de siyah kazanir.
          for(auto&dd:K){
            int x=f(bk)+dd[0], y=r(bk)+dd[1];
            if(x<0||x>7||y<0||y>7) continue;
            int obk=y*8+x;
            if(!ok(wk,obk,wq,br)) continue;
            int pi=idx(wk,obk,wq,br,1);
            if(!legal[pi]||res[pi]!=0) continue;
            res[pi]=-(d+1); buckets[d+1].push_back(pi);
          }
          for(auto&dd:RD){
            int x=f(br)+dd[0], y=r(br)+dd[1];
            while(x>=0&&x<=7&&y>=0&&y<=7){
              int obr=y*8+x;
              if(obr==wk||obr==bk||obr==wq) break;
              int pi=idx(wk,bk,wq,obr,1);
              if(legal[pi]&&res[pi]==0){
                res[pi]=-(d+1); buckets[d+1].push_back(pi);
              }
              x+=dd[0]; y+=dd[1];
            }
          }
        } else {
          // cur: siyah hamle, siyah kazaniyor -> onceki BEYAZ hamlesi;
          // butun beyaz hamleleri siyah kazanca gidiyorsa onceki de siyah kazanir.
          for(auto&dd:K){
            int x=f(wk)+dd[0], y=r(wk)+dd[1];
            if(x<0||x>7||y<0||y>7) continue;
            int owk=y*8+x;
            if(!ok(owk,bk,wq,br)) continue;
            int pi=idx(owk,bk,wq,br,0);
            if(!legal[pi]||res[pi]!=0||rem[pi]==0) continue;
            if(--rem[pi]==0){ res[pi]=-(d+1); buckets[d+1].push_back(pi); }
          }
          for(auto&dd:QD){
            int x=f(wq)+dd[0], y=r(wq)+dd[1];
            while(x>=0&&x<=7&&y>=0&&y<=7){
              int owq=y*8+x;
              if(owq==wk||owq==bk||owq==br) break;
              int pi=idx(wk,bk,owq,br,0);
              if(!legal[pi]||res[pi]!=0||rem[pi]==0){ x+=dd[0]; y+=dd[1]; continue; }
              if(--rem[pi]==0){ res[pi]=-(d+1); buckets[d+1].push_back(pi); }
              x+=dd[0]; y+=dd[1];
            }
          }
        }
      }
    }
  }

  // 4) ic tutarlilik kontrolu
  long long bad=0, whiteWins=0, blackWins=0, draws=0;
  int maxd=0;
  for(int i=0;i<N;i++){
    if(!legal[i]) continue;
    int16_t v=res[i];
    if(v>0){whiteWins++; if(v>maxd)maxd=v;}
    else if(v<0){blackWins++; if(-v>maxd)maxd=-v;}
    else {draws++; continue;}
    int stm=i&1, t=i>>1;
    int br=t&63;t>>=6;int wq=t&63;t>>=6;int bk=t&63;t>>=6;int wk=t&63;
    if(!ok(wk,bk,wq,br)){ bad++; continue; }
    if(stm==0) genWhite(wk,bk,wq,br,ch,caps,capCount); else genBlack(wk,bk,wq,br,ch,caps,capCount);
    bool moverIsWinner = (stm==0 && v>0) || (stm==1 && v<0);
    if(moverIsWinner && rem[i]>0){
      bool found = false;
      for(int c:caps) if(c==v) found=true;
      for(int c:ch) if((v>0 && res[c]==v-1) || (v<0 && res[c]==v+1)) found=true;
      if(!found) bad++;
    }
    // kaybeden tarafta butun cocuklar kazanan tarafin olmali, en az biri |v|-1
    if(!moverIsWinner){
      int wanted = v>0 ? v-1 : v+1;
      bool have=false;
      for(int c:ch){
        int16_t cv=res[c];
        if(v>0 ? cv<=0 : cv>=0) bad++;
        if(v>0 ? cv>v-1 : cv<v+1) bad++;
        if(cv==wanted) have=true;
      }
      // capture cocuklari tablo disi; kaybeden tarafta yakalama kazanca gidemez
      for(int c:caps) if((v>0 && c<=0) || (v<0 && c>=0)) bad++;
      if(!ch.empty() && !have) bad++;
    }
  }
  cerr<<"white="<<whiteWins<<" black="<<blackWins<<" draw="<<draws
      <<" maxDTM="<<maxd<<" bad="<<bad
      <<" time="<<chrono::duration<double>(chrono::steady_clock::now()-t0).count()<<"s\n";

  // 5) politika simulasyonu: secilmis konumlarda DTM kadar hamlede mat
  long long simBad=0, simOk=0;
  for(int sample=0; sample<200000; sample++){
    int wk=rand()%64, bk=rand()%64, wq=rand()%64, br=rand()%64, stm=rand()%2;
    if(!ok(wk,bk,wq,br)) continue;
    int start=idx(wk,bk,wq,br,stm);
    if(!legal[start] || res[start]==0) continue;
    int target=abs((int)res[start]);
    bool done=false, failed=false;
    for(int ply=0; ply<target; ply++){
      if(stm==0) genWhite(wk,bk,wq,br,ch,caps,capCount);
      else       genBlack(wk,bk,wq,br,ch,caps,capCount);
      int v=res[idx(wk,bk,wq,br,stm)];
      bool moverWins = (stm==0) ? v>0 : v<0;
      if(!moverWins && ch.empty() && capCount==0){
        bool inCheck = (stm==0) ? whiteKingInCheck(wk,wq,bk,br)
                                : blackKingInCheck(wk,wq,bk,br);
        if(inCheck) done=true; else failed=true;
        break;
      }
      bool moved=false;
      if(moverWins){
        for(int c:caps) if(c==v){ done=true; moved=true; break; }
        if(!moved){
          int want=(v>0)?v-1:v+1;
          for(int c:ch) if(res[c]==want){
            int t=c>>1; br=t&63;t>>=6;wq=t&63;t>>=6;bk=t&63;t>>=6;wk=t&63;
            moved=true;break;
          }
        }
      } else {
        int want=(v>0)?v-1:v+1;
        for(int c:ch) if(res[c]==want){
          int t=c>>1; br=t&63;t>>=6;wq=t&63;t>>=6;bk=t&63;t>>=6;wk=t&63;
          moved=true;break;
        }
      }
      if(!moved){ failed=true;break; }
      if(done) break;
      stm^=1;
    }
    if(failed) simBad++; else simOk++;
  }
  cerr<<"sim ok="<<simOk<<" bad="<<simBad<<"\n";

  vector<int8_t> out(N);
  for(int i=0;i<N;i++) out[i]=(int8_t)max(-127,min(127,(int)res[i]));
  fp=fopen("/tmp/opencode/kqkr.dat","wb");
  fwrite(out.data(),1,N,fp); fclose(fp);
  return 0;
}
